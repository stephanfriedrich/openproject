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
  module FileLinks
    class CopyFileLinksService < BaseService
      include OpenProject::LocaleHelper

      def self.call(source:, target:, user:, work_packages_map:)
        new(source:, target:, user:, work_packages_map:).call
      end

      def initialize(source:, target:, user:, work_packages_map:)
        super()
        @source = source
        @target = target
        @user = user
        @work_packages_map = work_packages_map.to_h { |key, value| [key.to_i, value.to_i] }
      end

      def call
        with_tagged_logger([self.class, @source.id, @target.id]) do
          source_file_links = FileLink.includes(:creator)
                                      .where(storage: @source.storage,
                                             container_id: @work_packages_map.keys,
                                             container_type: "WorkPackage")

          info "Found #{source_file_links.count} source file links"
          with_locale_for(@user) do
            info "Creating file links..."
            copy_file_links(source_file_links)
          end
        end
        info "File link creation finished"
        @result
      end

      private

      def copy_file_links(source_file_links)
        if @source.project_folder_automatic?
          create_managed_file_links(source_file_links).or do |error|
            log_adapter_error(error)
            @result.success = false
          end
        else
          create_unmanaged_file_links(source_file_links)
        end
      end

      def create_managed_file_links(source_file_links)
        info "Getting information about the source file links"
        source_files_info(source_file_links).bind do |source_info|
          info "Getting information about the copied target files"
          target_files_map.bind do |target_map|
            info "Building equivalency map..."
            location_map = build_location_map(source_info, target_map)

            info "Creating file links based on the location map #{location_map}"
            source_file_links.find_each do |source_link|
              target_location = location_map[source_link.origin_id]
              next if target_location.blank?

              create_target_file_link(source_link, target_location)
            end
            Success()
          end
        end
      end

      def create_target_file_link(source_link, remote_id)
        attributes = source_link.dup.attributes
        attributes.merge!(
          "storage_id" => @target.storage_id,
          "creator_id" => @user.id,
          "container_id" => @work_packages_map[source_link.container_id],
          "origin_id" => remote_id
        )

        CreateService.new(user: @user, contract_class: CopyContract).call(attributes)
      end

      def build_location_map(source_files, target_location_map)
        # We need this due to inconsistencies of how we represent the File Path
        target_location_map.transform_keys! { |key| key.starts_with?("/") ? key : "/#{key}" }

        source_files.to_h do |info|
          target = info.clean_location.gsub(@source.managed_project_folder_path, @target.managed_project_folder_path)

          [info.id.to_s, target_location_map[target]&.id || id]
        end
      end

      def auth_strategy
        Adapters::Registry.resolve("#{@source.storage}.authentication.userless").call
      end

      def source_files_info(source_file_links)
        Adapters::Input::FilesInfo.build(file_ids: source_file_links.pluck(:origin_id)).bind do |input_data|
          Adapters::Registry.resolve("#{@source.storage}.queries.files_info")
                            .call(storage: @source.storage, auth_strategy:, input_data:)
        end
      end

      def target_files_map
        Adapters::Input::FilePathToIdMap.build(folder: @target.project_folder_location).bind do |input_data|
          Adapters::Registry.resolve("#{@target.storage}.queries.file_path_to_id_map")
                            .call(storage: @target.storage, auth_strategy:, input_data:)
        end
      end

      def create_unmanaged_file_links(source_file_links)
        source_file_links.find_each do |source_file_link|
          attributes = source_file_link.dup.attributes
          attributes["storage_id"] = @target.storage_id
          attributes["creator_id"] = @user.id
          attributes["container_id"] = @work_packages_map[source_file_link.container_id]

          FileLinks::CreateService.new(user: @user, contract_class: CopyContract).call(attributes)
        end
      end
    end
  end
end
