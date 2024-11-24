# frozen_string_literal: true

#-- copyright
#++

module Storages
  module Adapters
    module Results
      StorageFile = Data.define(
        :id,
        :name,
        :size,
        :mime_type,
        :created_at,
        :last_modified_at,
        :created_by_name,
        :last_modified_by_name,
        :location,
        :permissions
      ) do
        def initialize(
          id:,
          name:,
          size: nil,
          mime_type: nil,
          created_at: nil,
          last_modified_at: nil,
          created_by_name: nil,
          last_modified_by_name: nil,
          location: nil,
          permissions: nil
        )
          super
        end

        def self.build(contract: StorageFileContract.new, **)
          contract.call(**).to_monad.fmap { |input| new(**input.to_h) }
        end

        def folder?
          mime_type.present? && mime_type == "application/x-op-directory"
        end
      end
    end
  end
end
