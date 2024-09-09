# frozen_string_literal:true

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
    module AuthenticationStrategies
      class OAuthUserToken < AuthenticationStrategy
        def initialize(user)
          @user = user
          @retried = false
          @error_data = Results::Error.new(source: self.class, code: :error)
        end

        # rubocop:disable Metrics/AbcSize
        def call(storage:, http_options: {}, &)
          oauth_client = validate_oauth_client(storage).value_or { return Failure(_1) }
          token = current_token(oauth_client).value_or { return Failure(_1) }

          options = http_options.deep_merge(headers: { "Authorization" => "Bearer #{token.access_token}" })

          original_response = yield OpenProject.httpx.with(options)

          case original_response
          in Failure(code: :unauthorized)
            refresh_and_retry(storage, token, options, &)
          else
            original_response
          end
        rescue ActiveRecord::StaleObjectError => e
          raise e if @retried

          Rails.logger.error("#{e.inspect} happened for User ##{@user.id} #{@user.name}")
          @retried = true
          retry
        end
        # rubocop:enable Metrics/AbcSize

        private

        def validate_oauth_client(storage)
          return Success(storage.oauth_client) if storage.oauth_client

          Failure(@error_data.with(code: :missing_oauth_client, payload: storage))
        end

        def refresh_and_retry(storage, token, options, &)
          config = storage.oauth_configuration.to_httpx_oauth_config.to_h
          refreshed_session = refresh_token(config, options, token).value_or { return Failure(_1) }
          update_token(token, refreshed_session)

          yield refreshed_session
        end

        def update_token(token, http_session)
          oauth_session = http_session.instance_variable_get(:@options).oauth_session
          token.update(access_token: oauth_session.access_token, refresh_token: oauth_session.refresh_token)
        end

        def refresh_token(oauth_config, options, token)
          httpx_config = oauth_config.merge(refresh_token: token.refresh_token, token_endpoint_auth_method: "client_secret_post")
          Success(OpenProject.httpx.oauth_auth(**httpx_config).with(options).with_access_token)
        rescue HTTPX::HTTPError => e
          handle_http_error(token, e)
        rescue HTTPX::TimeoutError => e
          handle_timeout(token, e)
        end

        def handle_timeout(token, exception)
          Rails.logger.error("Timeout while refreshing OAuth token. - Payload: #{exception.message}")
          token.destroy
          Failure(@error_data.with(error: :timeout_on_refresh, payload: exception))
        end

        def handle_http_error(token, error)
          Rails.logger.error("Error while refreshing OAuth token - Payload: #{error.response}")
          token.destroy
          Failure(@error_data.with(code: :unauthorized, payload: error.response))
        end

        def current_token(client)
          token = OAuthClientToken.find_by(user: @user, oauth_client: client)
          token ? Success(token) : Failure(@error_data.with(code: :unauthorized))
        end
      end
    end
  end
end
