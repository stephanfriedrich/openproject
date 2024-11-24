# frozen_string_literal: true

#-- copyright
#++

module Storages
  module Adapters
    module Results
      StorageFileCollection = Data.define(:files, :parent, :ancestors) do
        def self.build(files:, parent:, ancestors:, contract: StorageFileCollection.new)
          contract.new(files:, parent:, ancestors:).to_monad.fmap { |it| new(**it.to_h) }
        end
      end
    end
  end
end
