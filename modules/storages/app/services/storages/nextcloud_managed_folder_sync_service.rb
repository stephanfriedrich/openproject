# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Storages
  class NextcloudManagedFolderSyncService < BaseService
    using Peripherals::ServiceResultRefinements
    FILE_PERMISSIONS = OpenProject::Storages::Engine.external_file_permissions
    attr_reader :storage

    delegate :group_folder, :username, :id, :group, to: :@storage, private: true

    def self.i18n_key = "NextcloudSyncService"

    def self.call(storage)
      new(storage).call
    end

    def initialize(storage)
      super()
      @storage = storage
      setup_commands
    end

    # rubocop:disable Metrics/AbcSize
    def call
      return @result unless @storage.automatic_management_enabled?

      with_tagged_logger([self.class, "storage-#{id}"]) do
        info "Starting AMPF Sync for Nextcloud Storage #{@storage.id}"

        catch :failure do
          remote_folder_map.bind do |remote_folders|
            root_folder = remote_folders.delete("/#{group_folder}")
            prepare_root_folder(root_folder.id).bind do
              ensure_folders_exist(remote_folders.invert).bind { hide_inactive_folders(remote_folders.values.map(&:id)) }

              apply_permission_to_folders
              update_group
            end
          end
        end

        info "Finished AMPF Sync for Nextcloud Storage #{id}"
        @result
      end
    end
    # rubocop:enable Metrics/AbcSize

    private

    def prepare_root_folder(file_id)
      user_permissions = [
        { user_id: username, permissions: FILE_PERMISSIONS },
        { group_id: group, permissions: [:read_files] }
      ]

      info "Ensuring #{username} access on the #{group_folder} folder"
      Adapters::Input::SetPermissions.build(file_id:, user_permissions:).bind do |input_data|
        @commands[:set_permissions].call(auth_strategy:, input_data:).or do |error|
          add_error(:ensure_root_folder_permissions, error, options: { group_folder: })
          throw :failure
        end
      end
    end

    def ensure_folders_exist(id_map)
      info "Ensuring that automatically managed project folders exist and are correctly named."
      id_to_folder_map = id_map.transform_keys(&:id)

      active_project_storages_scope.includes(:project).map do |project_storage|
        folder_id = project_storage.project_folder_id
        next create_folder(project_storage) unless id_to_folder_map[folder_id]

        info "Checking the project folder needs to be renamed..."
        next if id_to_folder_map[folder_id] == project_storage.managed_project_folder_path.chop

        rename_folder(folder_id, project_storage.managed_project_folder_name)
      end

      Success(:setup_folders)
    end

    def hide_inactive_folders(existing_folder_ids)
      info "Hiding inactive folders..."
      user_permissions = [{ user_id: username, permissions: FILE_PERMISSIONS }, { group_id: group, permissions: [] }]
      active_folders = active_project_storages_scope.pluck(:project_folder_id)

      (existing_folder_ids - active_folders).each do |file_id|
        Adapters::Input::SetPermissions.build(user_permissions:, file_id:).bind do |input_data|
          @commands[:set_permissions].call(auth_strategy:, input_data:).or { |error| log_adapter_error(error) }
        end
      end

      Success(:hide_inactive_folders)
    end

    def apply_permission_to_folders
      info "Setting permissions to project folders"
      remote_admins = admin_remote_identities_scope.pluck(:origin_user_id)

      active_project_storages_scope
        .where.not(project_folder_id: nil)
        .order(:project_folder_id)
        .find_each do |project_storage|
        set_folder_permissions(remote_admins, project_storage)
      end

      info "Updating user access on automatically managed project folders"
      add_remove_users_to_group(@storage.group, @storage.username)

      active_project_storages_scope.includes(:project).where.not(project_folder_id: nil).find_each do |project_storage|
        user_permissions = folder_admin_permissions + non_admin_permissions(project_storage)
        info "Setting permissions for #{project_storage.managed_project_folder_name}..."
        set_permissions_on_folder(project_storage.project_folder_id, user_permissions)
      end

      Success(:apply_permission_to_folders)
    end

    def update_group
      Adapters::Input::GroupUsers.build(group:).bind do |group_data|
        @commands[:group_users].call(auth_strategy:, input_data: group_data).bind do |group_users|
          remote_users = group_users - [username]
          local_users = client_remote_identities_scope.pluck(:origin_user_id)

          add_users_to_group(local_users - remote_users)
          remove_users_from_group(remote_users - local_users)
        end
      end
    end

    ### Auxiliary methods

    def add_users_to_group(users)
      users.each do |user|
        Adapters::Input::AddUserToGroup.build(group:, user:).bind do |input_data|
          @commands[:add_user_to_group].call(auth_strategy:, input_data:).or { log_adapter_error(it) }
        end
      end
    end

    def audit_last_project_folder(project_storage, folder_info)
      ApplicationRecord.transaction do
        last_project_folder = LastProjectFolder.find_by(project_storage_id: project_storage.id, mode: :automatic)

        success = last_project_folder.update(origin_folder_id: folder_info.id) &&
          project_storage.update(project_folder_id: folder_info.id)

        raise ActiveRecord::Rollback unless success
      end
    end

    def create_folder(project_storage)
      info "Folder #{project_storage.managed_project_folder_path} does not exist. Creating..."
      Adapters::Input::CreateFolder
        .build(folder_name: project_storage.managed_project_folder_name, parent_location: group_folder).bind do |input_data|
        folder_info = @commands[:create_folder].call(auth_strategy:, input_data:).value_or do |error|
          add_error(:create_folder, error, options: input_data.to_h)
          throw :failure
        end

        audit_last_project_folder(project_storage, folder_info)
      end
    end

    def folder_admin_permissions
      admin_permissions = [{ user_id: username, permissions: FILE_PERMISSIONS }, { group_id: group, permissions: [] }]

      admin_remote_identities_scope.each_with_object(admin_permissions) do |identity, array|
        array << { user_id: identity.origin_user_id, permissions: FILE_PERMISSIONS }
      end
    end

    def non_admin_permissions(project_storage)
      project_remote_identities(project_storage).map do |identity|
        permissions = identity.user.all_permissions_for(project_storage.project) & FILE_PERMISSIONS

        { user_id: identity.origin_user_id, permissions: }
      end
    end

    def remote_folder_map
      info "Retrieving existing remote folder list"
      Adapters::Input::FilePathToIdMap.build(folder: group_folder, depth: 1).bind do |input_data|
        @commands[:file_path_to_id_map].call(auth_strategy:, input_data:).or do |error|
          add_error(:remote_folders, error, options: { username:, group_folder: })
          throw :failure
        end
      end
    end

    def remove_users_from_group(users)
      users.each do |user|
        Adapters::Input::RemoveUserFromGroup.build(group:, user:).bind do |input_data|
          @commands[:remove_user_from_group].call(auth_strategy:, input_data:).or { log_adapter_error(it) }
        end
      end
    end

    def rename_folder(location, new_name)
      info "Renaming project folder to #{new_name}"
      Adapters::Input::RenameFile.build(location:, new_name:).bind do |input_data|
        @commands[:rename_file].call(auth_strategy:, input_data:).or do |error|
          add_error(:rename_project_folder, error, options: input_data.to_h)
          throw :failure
        end
      end
    end

    def set_permissions_on_folder(file_id, user_permissions)
      Adapters::Input::SetPermissions.build(file_id:, user_permissions:).bind do |input_data|
        @commands[:set_permissions].call(auth_strategy:, input_data:).or { log_adapter_error(it) }
      end
    end

    ### MODEL SCOPES

    def project_remote_identities(project_storage)
      project_remote_identities = client_remote_identities_scope.where.not(id: admin_remote_identities_scope).order(:id)

      if project_storage.project.public? && ProjectRole.non_member.permissions.intersect?(FILE_PERMISSIONS)
        project_remote_identities
      else
        project_remote_identities.where(user: project_storage.project.users)
      end
    end

    def active_project_storages_scope
      @storage.project_storages.active.automatic
    end

    def client_remote_identities_scope
      RemoteIdentity.includes(:user).where(integration: @storage)
    end

    def admin_remote_identities_scope
      remote_identities_scope.where(user: User.admin.active)
    end

    #### ADAPTER COMMANDS/QUERIES

    def auth_strategy
      @auth_strategy ||= Adapters::Registry["nextcloud.authentication.userless"].call
    end

    def setup_commands
      @commands = %w[nextcloud.commands.create_folder nextcloud.commands.rename_file nextcloud.commands.set_permissions
                     nextcloud.queries.file_path_to_id_map nextcloud.queries.group_users nextcloud.commands.add_user_to_group
                     nextcloud.commands.remove_user_from_group].each_with_object({}) do |key, hash|
        hash[key.split(".").last.to_sym] = Adapters::Registry[key].new(@storage)
      end
    end
  end
end
