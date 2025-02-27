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

require "spec_helper"
require_module_spec_helper

RSpec::Matchers.define_negated_matcher :not_change, :change

module Storages
  FakeProject = Data.define(:id, :name)

  class TestIdentifier < Adapters::Providers::Nextcloud::ManagedFolderIdentifier
    def initialize(project_storage)
      super
      @project = FakeProject.new(-273, project_storage.project.name)
    end
  end

  RSpec.describe NextcloudManagedFolderSyncService, :webmock do
    subject(:service) { described_class.new(storage) }

    shared_let(:storage) { create(:nextcloud_storage_with_local_connection, :as_automatically_managed) }
    shared_let(:oauth_client) { storage.oauth_client }
    # USER FACTORIES
    shared_let(:admin) { create(:admin) }
    shared_let(:admin_identity) { create(:remote_identity, user: admin, oauth_client:, origin_user_id: "anakin") }
    shared_let(:single_project_user) { create(:user) }
    shared_let(:single_project_user_token) do
      create(:remote_identity, user: single_project_user, oauth_client:, origin_user_id: "luke")
    end

    shared_let(:multiple_projects_user) { create(:user) }
    shared_let(:multiple_project_user_token) do
      create(:remote_identity, user: multiple_projects_user, oauth_client:, origin_user_id: "leia")
    end

    # ROLE FACTORIES
    shared_let(:ordinary_role) { create(:project_role, permissions: %w[read_files write_files]) }
    shared_let(:read_only_role) { create(:project_role, permissions: %w[read_files]) }
    shared_let(:non_member_role) { create(:non_member, permissions: %w[read_files]) }

    # PROJECT FACTORIES
    shared_let(:project) do
      create(:project,
             name: "[Sample] Project Name / Ehuu",
             members: { multiple_projects_user => ordinary_role, single_project_user => ordinary_role })
    end
    shared_let(:project_storage) do
      create(:project_storage, :with_historical_data, project_folder_mode: "automatic", storage:, project:)
    end

    shared_let(:disallowed_chars_project) do
      create(:project, name: '<=o=> | "Jedi" Project Folder ///', members: { multiple_projects_user => ordinary_role })
    end
    shared_let(:disallowed_chars_project_storage) do
      create(:project_storage, :with_historical_data, project_folder_mode: "automatic", project: disallowed_chars_project,
                                                      storage:)
    end

    shared_let(:inactive_project) do
      create(:project, name: "INACTIVE PROJECT! f0r r34lz", active: false, members: { multiple_projects_user => ordinary_role })
    end
    shared_let(:inactive_project_storage) do
      create(:project_storage, :with_historical_data, project_folder_mode: "automatic", project: inactive_project, storage:)
    end

    shared_let(:public_project) { create(:public_project, name: "PUBLIC PROJECT", active: true) }
    shared_let(:public_project_storage) do
      create(:project_storage, :with_historical_data, project_folder_mode: "automatic", project: public_project, storage:)
    end

    shared_let(:unmanaged_project) do
      create(:project, name: "Non Managed Project", active: true, members: { multiple_projects_user => ordinary_role })
    end
    shared_let(:unmanaged_project_storage) do
      create(:project_storage, :with_historical_data, project_folder_mode: "manual", project: unmanaged_project, storage:)
    end

    it "responds to .call" do
      method = described_class.method(:call)

      expect(method.parameters).to contain_exactly(%i[req storage])
    end

    it "return if the storage is not automatically managed" do
      storage = create(:nextcloud_storage_configured)
      expect(described_class.call(storage)).to be_success
    end

    describe "#call" do
      before do
        Adapters::Registry.stub("nextcloud.models.managed_folder_identifier", TestIdentifier)
      end

      after { delete_created_folders }

      describe "Remote Folder Creation" do
        it "updates the project folder id for all active automatically managed projects",
           vcr: "nextcloud/sync_service_create_folder" do
          expect { service.call }.to change { disallowed_chars_project_storage.reload.project_folder_id }
                                    .from(nil).to(String)
                                    .and(change { project_storage.reload.project_folder_id }.from(nil).to(String))
                                    .and(change { public_project_storage.reload.project_folder_id }.from(nil).to(String))
                                    .and(not_change { inactive_project_storage.reload.project_folder_id })
                                    .and(not_change { unmanaged_project_storage.reload.project_folder_id })
        end

        it "adds a record to the LastProjectFolder for each new folder",
           vcr: "nextcloud/sync_service_create_folder" do
          scope = ->(project_storage) { LastProjectFolder.where(project_storage:).last }

          expect { service.call }.to not_change { scope[unmanaged_project_storage].reload.origin_folder_id }
                                       .and(not_change { scope[inactive_project_storage].reload.origin_folder_id })

          expect(scope[project_storage].origin_folder_id).to eq(project_storage.reload.project_folder_id)
          expect(scope[public_project_storage].origin_folder_id).to eq(public_project_storage.reload.project_folder_id)
          expect(scope[disallowed_chars_project_storage].origin_folder_id)
            .to eq(disallowed_chars_project_storage.reload.project_folder_id)
        end

        it "creates the remote folders for all projects with automatically managed folders enabled",
           vcr: "nextcloud/sync_service_create_folder" do
          service.call

          [project_storage, disallowed_chars_project_storage, public_project_storage].each do |proj_storage|
            expect(project_folder_info(proj_storage)).to be_success
          end
        end

        it "makes sure that the last_project_folder.origin_folder_id match the current project_folder_id",
           vcr: "nextcloud/sync_service_create_folder" do
          service.call

          [project_storage, disallowed_chars_project_storage, public_project_storage].each do |proj_storage|
            proj_storage.reload
            the_real_last_project_folder = proj_storage.last_project_folders.last

            expect(proj_storage.project_folder_id).to eq(the_real_last_project_folder.origin_folder_id)
          end
        end
      end

      it "renames an already existing project folder", vcr: "nextcloud/sync_service_rename_folder" do
        create_folder_for(disallowed_chars_project_storage, "Old Jedi Project").bind do |original_folder|
          disallowed_chars_project_storage.update(project_folder_id: original_folder.id)
        end

        service_result = service.call
        expect(service_result).to be_success
        expect(service_result.errors).to be_empty

        result = project_folder_info(disallowed_chars_project_storage.reload).value!
        expect(result.name).to match(%r{<=o=> | "Jedi" Project Folder ||| \(-273\)})
      end

      it "hides (removes all permissions) from inactive project folders", vcr: "nextcloud/sync_service_hide_inactive" do
        create_folder_for(inactive_project_storage).bind do |original_folder|
          inactive_project_storage.update(project_folder_id: original_folder.id)

          # add_users_to_group(%w[anakin leia luke])
          set_permissions_on(original_folder.id,
                             [{ user_id: "anakin", permissions: [:read_files] },
                              { user_id: "luke", permissions: [:write_files] }])
        end

        result = service.call

        expect(result).to be_success
        expect(result.errors).to be_empty
        users = permissions_for(inactive_project_storage).map { |hash| hash[:user_id] }

        # Group, User
        expect(users).to contain_exactly("OpenProject", "OpenProject")
      end

      it "adds already logged in users to the project folder", vcr: "nextcloud/sync_service_set_permissions" do
        create_folder_for(inactive_project_storage).bind do |original_folder|
          inactive_project_storage.update(project_folder_id: original_folder.id)
        end

        service.call

        # Group, user1, user2...
        expect(permissions_for(project_storage)).to contain_exactly(
          { user_id: "OpenProject", permissions: [] },
          { user_id: "OpenProject", permissions: described_class::FILE_PERMISSIONS },
          { user_id: "anakin", permissions: described_class::FILE_PERMISSIONS },
          { user_id: "luke", permissions: %i[read_files write_files] },
          { user_id: "leia", permissions: %i[read_files write_files] }
        )

        expect(permissions_for(disallowed_chars_project_storage)).to contain_exactly(
          { user_id: "OpenProject", permissions: [] },
          { user_id: "OpenProject", permissions: described_class::FILE_PERMISSIONS },
          { user_id: "anakin", permissions: described_class::FILE_PERMISSIONS },
          { user_id: "leia", permissions: %i[read_files write_files] }
        )

        expect(permissions_for(inactive_project_storage)).to contain_exactly(
          { user_id: "OpenProject", permissions: [] },
          { user_id: "OpenProject", permissions: described_class::FILE_PERMISSIONS }
        )
      end

      it "if the project is public allows any logged in user to read the files", vcr: "nextcloud/sync_service_public_project" do
        service.call

        expect(permissions_for(public_project_storage)).to contain_exactly(
          { user_id: "OpenProject", permissions: [] },
          { user_id: "OpenProject", permissions: described_class::FILE_PERMISSIONS },
          { user_id: "anakin", permissions: described_class::FILE_PERMISSIONS },
          { user_id: "admin", permissions: [:read_files] },
          { user_id: "luke", permissions: [:read_files] },
          { user_id: "leia", permissions: [:read_files] }
        )
      end

      it "ensures that admins have full access to all folders", vcr: "nextcloud/sync_service_admin_access" do
        service.call

        [project_storage, disallowed_chars_project_storage, public_project_storage].each do |ps|
          expect(permissions_for(ps))
            .to include({ user_id: "anakin", permissions: %i[read_files write_files create_files delete_files share_files] })
        end
      end

      it "adds and remove users from the remote group", vcr: "nextcloud/sync_service_group_users" do
        service.call

        users = Adapters::Input::GroupUsers.build(group: storage.group).bind do |input_data|
          Adapters::Registry["nextcloud.queries.group_users"].call(storage:, auth_strategy:, input_data:).value!
        end

        expect(users).to match_array(%w[OpenProject anakin luke leia admin])
      ensure
        %w[anakin luke leia].each do |user|
          Adapters::Input::RemoveUserFromGroup.build(group: storage.group, user:).bind do |input_data|
            Adapters::Registry["nextcloud.commands.remove_user_from_group"].call(storage:, auth_strategy:, input_data:)
          end
        end
      end

      describe "error handling" do
        let(:error_key_prefix) { "services.errors.models.nextcloud_sync_service" }

        before { allow(Rails.logger).to receive_messages(%i[error warn]) }

        context "when reading the root folder fails" do
          before { storage.update(password: "THIS_IS_AS_SECURE_AS_DEATH_STAR_VENTILATION_PORT") }

          it "returns a failure in case retrieving the root list fails", vcr: "nextcloud/sync_service_root_read_failure" do
            result = service.call

            expect(result).to be_failure
            expect(result.errors[:base])
              .to match_array(I18n.t("#{error_key_prefix}.unauthorized", username: "OpenProject", group_folder: "OpenProject"))
          end

          it "logs the occurrence", vcr: "nextcloud/sync_service_root_read_failure" do
            service.call

            expect(Rails.logger)
              .to have_received(:error).with(error_code: :unauthorized,
                                             group_folder: "OpenProject",
                                             username: "OpenProject",
                                             data: { body: /unable to complete your request/, status: 401 })
          end
        end

        context "when folder creation fails" do
          it "doesn't update the project_storage", vcr: "nextcloud/sync_service_creation_fail" do
            already_existing_folder = create_folder_for(project_storage).value!
            result = nil

            expect { result = service.call }.not_to change(project_storage, :project_folder_id)

            expect(result).to be_failure
            expect(result.errors[:create_folder])
              .to match_array(I18n.t("#{error_key_prefix}.attributes.create_folder.conflict",
                                     folder_name: project_storage.managed_project_folder_name,
                                     parent_location: storage.group_folder))
          ensure
            delete_folder(already_existing_folder.id)
          end

          it "logs the occurrence", vcr: "nextcloud/sync_service_creation_fail" do
            already_existing_folder = create_folder_for(project_storage).value!
            service.call

            expect(Rails.logger)
              .to have_received(:error)
                    .with(folder_name: "[Sample] Project Name | Ehuu (-273)",
                          error_code: :conflict,
                          parent_location: Peripherals::ParentFolder.new(storage.group_folder),
                          data: { body: String, status: 405 })
          ensure
            delete_folder(already_existing_folder.id)
          end
        end

        context "when folder renaming fails" do
          it "adds an error and logs the occurrence", vcr: "nextcloud/sync_service_rename_failed" do
            create_folder_for(project_storage)
            original_folder = create_folder_for(project_storage, "Flawless Death Star Blueprints").value!
            project_storage.update(project_folder_id: original_folder.id)

            result = service.call
            expect(result).to be_failure

            expect(result.errors[:rename_project_folder])
              .to match_array(I18n.t("#{error_key_prefix}.attributes.rename_project_folder.conflict",
                                     new_name: project_storage.managed_project_folder_name))

            expect(Rails.logger)
              .to have_received(:error).with(location: Peripherals::ParentFolder.new(original_folder.id),
                                             new_name: "[Sample] Project Name | Ehuu (-273)",
                                             error_code: :conflict,
                                             data: { body: String, status: 412 })
          ensure
            delete_folder(original_folder.location)
          end
        end
      end
    end

    private

    def permissions_for(project_storage)
      Adapters::Authentication[auth_strategy].call(storage:) do |http|
        request_url = UrlBuilder.url(storage.uri, "remote.php/dav/files", storage.username,
                                     project_storage.managed_project_folder_path)
        response = http.request(:propfind, request_url, xml: permission_request_body)
        parse_acl_xml response.body.to_s
      end
    end

    def permission_request_body
      Nokogiri::XML::Builder.new do |xml|
        xml["d"].propfind(
          "xmlns:d" => "DAV:",
          "xmlns:nc" => "http://nextcloud.org/ns"
        ) do
          xml["d"].prop do
            xml["nc"].send(:"acl-list")
          end
        end
      end.to_xml
    end

    def parse_acl_xml(xml)
      found_code = "d:status[text() = 'HTTP/1.1 200 OK']"
      not_found_code = "d:status[text() = 'HTTP/1.1 404 Not Found']"
      happy_path = "/d:multistatus/d:response/d:propstat[#{found_code}]/d:prop/nc:acl-list"
      not_found_path = "/d:multistatus/d:response/d:propstat[#{not_found_code}]/d:prop"

      if Nokogiri::XML(xml).xpath(not_found_path).children.map(&:name).include?("acl-list")
        []
      else
        Nokogiri::XML(xml).xpath(happy_path).children.map do |acl|
          acl.children.each_with_object({ user_id: "", permissions: [] }) do |entry, agg|
            agg[:user_id] = entry.text if entry.name == "acl-mapping-id"
            agg[:permissions] = translate_mask_to_permissions(entry.text.to_i) if entry.name == "acl-permissions"
          end
        end
      end
    end

    def translate_mask_to_permissions(number)
      Adapters::Providers::Nextcloud::Commands::SetPermissionsCommand::PERMISSIONS_MAP
        .each_with_object([]) { |(permission, mask), list| list << permission if number & mask == mask }
    end

    def set_permissions_on(file_id, user_permissions)
      Adapters::Input::SetPermissions.build(user_permissions:, file_id:).bind do |input_data|
        Adapters::Registry["nextcloud.commands.set_permissions"].call(storage:, auth_strategy:, input_data:)
      end
    end

    def create_folder_for(project_storage, folder_override = nil)
      folder_name = folder_override || project_storage.managed_project_folder_name
      Adapters::Input::CreateFolder.build(parent_location: storage.group_folder, folder_name:).bind do |input_data|
        Adapters::Registry["nextcloud.commands.create_folder"].call(storage:, auth_strategy:, input_data:)
      end
    end

    def original_folders
      root_folder_contents.fmap do |storage_files|
        storage_files.files.find { |file| file.id == project_storage.project_folder_id }
      end
    end

    def project_folder_info(project_storage)
      root_folder_contents.fmap do |storage_files|
        storage_files.files.find { |file| file.id == project_storage.reload.project_folder_id }
      end
    end

    def root_folder_contents
      Adapters::Input::Files.build(folder: storage.group_folder).bind do |input_data|
        Adapters::Registry["nextcloud.queries.files"].call(storage:, auth_strategy:, input_data:)
      end
    end

    def delete_created_folders
      storage.project_storages.automatic
             .where(storage:)
             .where.not(project_folder_id: nil)
             .find_each { |project_storage| delete_folder(project_storage.managed_project_folder_path.chop) }
    end

    def delete_folder(item_id)
      Adapters::Input::DeleteFolder.build(location: item_id).bind do |input_data|
        Adapters::Registry["nextcloud.commands.delete_folder"].call(storage:, auth_strategy:, input_data:)
      end
    end

    def auth_strategy
      Adapters::Registry["nextcloud.authentication.userless"].call
    end
  end
end
