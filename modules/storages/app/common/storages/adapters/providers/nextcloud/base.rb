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
  module Adapters
    module Providers
      module Nextcloud
        class Base
          include TaggedLogging
          include Dry::Monads::Result(Results::Error)

          def self.call(storage:, auth_strategy:, input_data:)
            new(storage).call(auth_strategy: auth_strategy, input_data: input_data)
          end

          def initialize(storage)
            @storage = storage
          end

          private

          def origin_user_id(auth_strategy:)
            error = Results::Error.new(source: self.class, code: :error)

            auth_strategy.bind do |strategy|
              case strategy.key
              when :basic_auth
                Success(@storage.username)
              when :oauth_user_token
                remote_id = RemoteIdentity.of_user_and_client(strategy.user, @storage.oauth_client)
                if remote_id.present?
                  Success(remote_id.origin_user_id)
                else
                  Failure(
                    error.with(payload: "No origin user ID or user token found. Cannot execute query without user context.")
                  )
                end
              else
                Failure(
                  error.with(
                    payload: "authentication strategy with user context found. Cannot execute query without user context."
                  )
                )
              end
            end
          end
        end
      end
    end
  end
end
