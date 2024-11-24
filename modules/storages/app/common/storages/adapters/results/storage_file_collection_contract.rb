# frozen_string_literal: true

module Storages
  module Adapters
    module Results
      class StorageFileCollectionContract < Dry::Validation::Contract
        params do
          required(:files).array(AdapterTypes::StorageFileInstance)
          required(:parent).filled(AdapterTypes::StorageFileInstance)
          required(:ancestors).array(AdapterTypes::StorageFileInstance)
        end
      end
    end
  end
end
