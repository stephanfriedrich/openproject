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

module Storages
  module Adapters
    module Providers
      module Nextcloud
        module Queries
          RSpec.describe FilesInfoQuery, :webmock do
            let(:user) { create(:user) }
            let(:auth_strategy) { Registry["nextcloud.authentication.user_bound"].call(user) }
            let(:storage) do
              create(:nextcloud_storage_with_local_connection, :as_not_automatically_managed, oauth_client_token_user: user)
            end

            let(:input_data) { Input::FilesInfo.build(file_ids:).value! }

            subject { described_class.new(storage) }

            describe "#call" do
              let(:file_ids) { %w[182 203 222] }

              context "without outbound request involved" do
                context "with an empty array of file ids" do
                  let(:file_ids) { [] }

                  it "returns an empty array" do
                    result = subject.call(auth_strategy:, input_data:)

                    expect(result).to be_success
                    expect(result.value!).to eq([])
                  end
                end
              end

              context "with outbound request successful", vcr: "nextcloud/files_info_query_success" do
                context "with an array of file ids" do
                  it "must return an array of file information when called" do
                    result = subject.call(auth_strategy:, input_data:)
                    expect(result).to be_success

                    file_infos = result.value!
                    expect(file_infos.size).to eq(3)
                    expect(file_infos).to all(be_a(Results::StorageFileInfo))
                  end
                end
              end

              context "with outbound request not found" do
                context "with a single file id", vcr: "nextcloud/files_info_query_not_found" do
                  let(:file_ids) { %w[1234] }

                  it "returns an HTTP 200 with individual status code per file ID" do
                    result = subject.call(auth_strategy:, input_data:)
                    expect(result).to be_success

                    file_infos = result.value!
                    expect(file_infos.size).to eq(1)
                    expect(file_infos.first.to_h).to include(status: "Not Found", status_code: 404)
                  end
                end
              end

              context "with outbound request not authorized" do
                context "with multiple file IDs, one of which is not authorized",
                        vcr: "nextcloud/files_info_query_only_one_not_authorized" do
                  let(:file_ids) { %w[182 1234] }

                  it "returns an HTTP 200 with individual status code per file ID" do
                    result = subject.call(auth_strategy:, input_data:)
                    expect(result).to be_success

                    file_infos = result.value!
                    expect(file_infos.size).to eq(2)
                    expect(file_infos.map(&:status_code)).to contain_exactly(403, 404)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
