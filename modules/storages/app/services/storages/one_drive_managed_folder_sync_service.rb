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
  class OneDriveManagedFolderSyncService < BaseService
    using Peripherals::ServiceResultRefinements

    OP_PERMISSIONS = %i[read_files write_files create_files delete_files share_files].freeze

    def self.i18n_key = "OneDriveSyncService"

    def self.call(storage)
      new(storage).call
    end

    def initialize(storage)
      @storage = storage
      @result = ServiceResult.success(errors: ActiveModel::Errors.new(self))
      setup_commands
    end

    def call
      with_tagged_logger([self.class.name, "storage-#{@storage.id}"]) do
        return unless @storage.automatic_management_enabled?

        info "Starting AMPF Sync for OneDrive Storage #{@storage.id}"
        existing_remote_folders = remote_folders_map(@storage.drive_id).value_or { return @result }

        ensure_folders_exist(existing_remote_folders).bind { hide_inactive_folders(existing_remote_folders) }
        apply_permission_to_folders

        @result
      end
    end

    private

    # rubocop:disable Metrics/AbcSize
    def apply_permission_to_folders
      info "Setting permissions to project folders"
      active_project_storages_scope.includes(:project).where.not(project_folder_id: nil).find_each do |project_storage|
        permissions = admin_remote_identities_scope.pluck(:origin_user_id).map do |origin_user_id|
          { user_id: origin_user_id, permissions: [:write_files] }
        end

        project_remote_identities(project_storage).each do |identity|
          add_user_to_permission_list(permissions, identity, project_storage.project)
        end

        info "Setting permissions for #{project_storage.managed_project_folder_name}: #{permissions}"

        project_folder_id = project_storage.project_folder_id
        build_permissions_input_data(project_folder_id, permissions)
          .either(
            ->(input_data) { @commands[:set_permissions].call(auth_strategy:, input_data:) },
            ->(failure) { log_validation_error(failure, project_folder_id:, permissions:) }
          )
      end
    end
    # rubocop:enable Metrics/AbcSize

    def ensure_folders_exist(folder_map)
      info "Ensuring that automatically managed project folders exist and are correctly named."
      active_project_storages_scope.includes(:project).find_each do |project_storage|
        unless folder_map.key?(project_storage.project_folder_id)
          info "#{project_storage.managed_project_folder_path} does not exist. Creating..."
          next create_remote_folder(project_storage.managed_project_folder_path, project_storage.id)
        end

        rename_project_folder(folder_map[project_storage.project_folder_id], project_storage)
      end

      Success(:folder_maintenance_done)
    end

    def hide_inactive_folders(folder_map)
      info "Hiding folders related to inactive projects"

      inactive_folder_ids(folder_map).each { |item_id| hide_folder(item_id, folder_map) }
    end

    def hide_folder(item_id, folder_map)
      info "Hiding folder with ID #{item_id} as it does not belong to any active project"

      build_permissions_input_data(item_id, [])
        .either(
          ->(input_data) do
            @commands[:set_permissions].call(auth_strategy:, input_data:).or do |error|
              log_adapter_error(error, item_id:, context: "hide_folder")
              add_error(:hide_inactive_folders, error, options: { path: folder_map[item_id] })
            end
          end,
          ->(failure) { log_validation_error(failure, item_id:, context: "hide_folder") }
        )
    end

    def inactive_folder_ids(folder_map)
      folder_map.keys - active_project_storages_scope.pluck(:project_folder_id).compact
    end

    def add_user_to_permission_list(permissions, identity, project)
      op_user_permissions = identity.user.all_permissions_for(project)

      if op_user_permissions.include?(:write_files)
        permissions << { user_id: identity.origin_user_id, permissions: [:write_files] }
      elsif op_user_permissions.include?(:read_files)
        permissions << { user_id: identity.origin_user_id, permissions: [:read_files] }
      end
    end

    def rename_project_folder(current_folder_name, project_storage)
      actual_path = project_storage.managed_project_folder_path
      return if current_folder_name == actual_path

      info "#{current_folder_name} is misnamed. Renaming to #{actual_path}"
      folder_id = project_storage.project_folder_id

      Adapters::Input::RenameFile.build(location: folder_id, new_name: actual_path).bind do |input_data|
        @commands[:rename_file].call(auth_strategy:, input_data:).or do |error|
          log_adapter_error(error, folder_id:, folder_name: actual_path)
          add_error(
            :rename_project_folder, error,
            options: { current_path: current_folder_name, project_folder_name: actual_path, project_folder_id: folder_id }
          )
        end
      end
    end

    def create_remote_folder(folder_name, project_storage_id)
      input_data = Adapters::Input::CreateFolder.build(folder_name:, parent_location: "/").value_or do |it|
        log_validation_error(it, folder_name: folder_name, parent_location: "/")
        return Failure(it)
      end

      folder_info = @commands[:create_folder].call(auth_strategy:, input_data:).value_or do |error|
        log_adapter_error(error, folder_name:)
        return add_error(:create_folder, error, options: { folder_name:, parent_location: "/" })
      end

      last_project_folder = LastProjectFolder.find_by(project_storage_id:, mode: :automatic)

      audit_last_project_folder(last_project_folder, folder_info.id)
    end

    def audit_last_project_folder(last_project_folder, project_folder_id)
      ApplicationRecord.transaction do
        success =
          last_project_folder.update(origin_folder_id: project_folder_id) &&
            last_project_folder.project_storage.update(project_folder_id:)

        raise ActiveRecord::Rollback unless success
      end
    end

    def remote_folders_map(drive_id)
      info "Retrieving already existing folders under #{drive_id}"

      input_data = Adapters::Input::Files.build(folder: "/").value_or do |it|
        log_validation_error(it, context: "remote_folders")
        return Failure()
      end

      file_list = @commands[:files].call(auth_strategy:, input_data:).value_or do |error|
        log_adapter_error(error, { drive_id: })
        add_error(:remote_folders, error, options: { drive_id: }).fail!
        return Failure()
      end

      Success(filter_folders_from(file_list.files))
    end

    # @param files [Array<Storages::StorageFile>]
    # @return Hash{String => String} a hash of item ID and item name.
    def filter_folders_from(files)
      folders = files.each_with_object({}) do |file, hash|
        next unless file.folder?

        hash[file.id] = file.name
      end

      info "Found #{folders.size} folders. Map: #{folders}"

      folders
    end

    def project_remote_identities(project_storage)
      project_remote_identities = client_remote_identities_scope.where.not(id: admin_remote_identities_scope).order(:id)

      if project_storage.project.public? && ProjectRole.non_member.permissions.intersect?(OP_PERMISSIONS)
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
      client_remote_identities_scope.where(user: User.admin.active)
    end

    def build_permissions_input_data(file_id, user_permissions)
      Adapters::Input::SetPermissions.build(file_id:, user_permissions:)
    end

    # @param attribute [Symbol] attribute to which the error will be tied to
    # @param error [Storages::Adapters::Results::Error] An adapter error result
    # @param options [Hash{Symbol => Object}] optional extra parameters for the message generation
    # @return ServiceResult
    def add_error(attribute, error, options: {})
      if %i[error unauthorized].include? error.code
        @result.errors.add(:base, error.code, **options)
      else
        @result.errors.add(attribute, error.code, **options)
      end

      @result
    end

    def auth_strategy
      @auth_strategy ||= Adapters::Registry["one_drive.authentication.userless"].call
    end

    def setup_commands
      @commands = %w[one_drive.commands.create_folder one_drive.commands.rename_file
                     one_drive.commands.set_permissions one_drive.queries.files].each_with_object({}) do |key, hash|
        hash[key.split(".").last.to_sym] = Adapters::Registry[key].new(@storage)
      end
    end
  end
end
