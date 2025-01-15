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
  class CreateFolderService < BaseService
    using Peripherals::ServiceResultRefinements

    def self.call(storage:, user:, name:, parent_id:)
      new(storage).call(user:, name:, parent_id:)
    end

    def initialize(storage)
      super()
      @storage = storage
    end

    def call(user:, name:, parent_id:)
      auth_strategy = Adapters::Registry.resolve("#{@storage}.authentication.user_bound").call(user)
      parent_location = parent_path(parent_id, user).on_failure { return _1 }.result

      Adapters::Input::CreateFolder.build(folder_name: name, parent_location:).bind do |input_data|
        Adapters::Registry.resolve("#{@storage}.commands.create_folder")
                          .call(storage: @storage, auth_strategy:, input_data:)
                          .either(
                            ->(folder) { ServiceResult.success(result: folder) },
                            ->(failure) { ServiceResult.failure(errors: failure) }
                          )
      end
    end

    private

    def parent_path(parent_id, user)
      case @storage.short_provider_type
      when "nextcloud"
        location_from_file_info(parent_id, user)
      when "one_drive"
        ServiceResult.success(result: parent_id)
      else
        raise "Unknown Storage Type"
      end
    end

    def location_from_file_info(parent_id, user)
      StorageFileService.call(storage: @storage, user:, file_id: parent_id).on_success do |success|
        path = URI.decode_uri_component(success.result.location)
        return ServiceResult.success(result: path)
      end
    end
  end
end
