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
      class OAuthClientCredentials < AuthenticationStrategy
        TOKEN_CACHE_KEY = "storage.%s.httpx_access_token"

        def initialize(use_cache)
          super()
          @use_cache = use_cache
        end

        def call(storage:, http_options: {})
          config = validate_configuration(storage).value_or { return Failure(it) }

          token_cache_key = TOKEN_CACHE_KEY % storage.id
          access_token = @use_cache ? Rails.cache.read(token_cache_key) : nil

          http = build_http_session(access_token, config, http_options).value_or { return Failure(it) }

          operation_result = yield http

          return operation_result unless @use_cache

          case operation_result
          in Success if @use_cache && access_token.blank?
            write_cache(token_cache_key, http)
          in Failure(code: :forbidden)
            clear_cache(token_cache_key)
          else
            return operation_result
          end

          operation_result
        end

        private

        def validate_configuration(storage)
          config = storage.oauth_configuration.to_httpx_oauth_config
          return Success(config) if config.valid?

          Failure(Results::Error.new(source: self.class, payload: storage, code: :storage_not_configured))
        end

        def write_cache(key, httpx_session)
          access_token = httpx_session.instance_variable_get(:@options).oauth_session.access_token
          Rails.cache.write(key, access_token, expires_in: 50.minutes)
        end

        def clear_cache(key) = Rails.cache.delete(key)

        def build_http_session(access_token, config, http_options)
          if access_token.present?
            http_with_current_token(access_token:, http_options:)
          else
            http_with_new_token(config:, http_options:)
          end
        end

        def http_with_current_token(access_token:, http_options:)
          opts = http_options.deep_merge({ headers: { "Authorization" => "Bearer #{access_token}" } })
          Success(OpenProject.httpx.with(opts))
        end

        def http_with_new_token(config:, http_options:)
          http = OpenProject.httpx
                            .oauth_auth(**config.to_h, token_endpoint_auth_method: "client_secret_post")
                            .with_access_token
                            .with(http_options)
          Success(http)
        rescue HTTPX::HTTPError => e
          Failure(Results::Error.new(code: :unauthorized, payload: e.response, source: self.class))
        rescue HTTPX::TimeoutError => e
          Failure(Results::Error.new(code: :timeout, payload: e.to_s, source: self.class))
        end
      end
    end
  end
end
