# frozen_string_literal: true

#-- copyright
#++

module Storages
  module Adapters
    module Results
      class StorageFileContract < Dry::Validation::Contract
        params do
          before(:value_coercer) do |input|
            input.to_h.compact
          end

          required(:id).filled(:string)
          required(:name).filled(:string)
          optional(:size).filled(:integer, gteq?: 0)
          optional(:mime_type).filled(:string)
          optional(:created_at).filled(:time)
          optional(:last_modified_at).filled(:time)
          optional(:created_by_name).filled(:string)
          optional(:last_modified_by_name).filled(:string)
          optional(:location).filled(:string, format?: /^\//)
          optional(:permissions).value(:array)
        end
      end
    end
  end
end
