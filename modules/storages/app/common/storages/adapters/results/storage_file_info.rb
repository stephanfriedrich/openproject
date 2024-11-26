#-- copyright
#++

module Storages
  module Adapters
    module Results
      # TODO: Unify StorageFile and StorageFileInfo as one is a subset of the other
      StorageFileInfo = Data.define(
        :status,
        :status_code,
        :id,
        :name,
        :last_modified_at,
        :created_at,
        :mime_type,
        :size,
        :owner_name,
        :owner_id,
        :last_modified_by_name,
        :last_modified_by_id,
        :permissions,
        :location
      ) do
        def initialize(
          status:,
          status_code:,
          id:,
          name: nil,
          last_modified_at: nil,
          created_at: nil,
          mime_type: nil,
          size: nil,
          owner_name: nil,
          owner_id: nil,
          last_modified_by_name: nil,
          last_modified_by_id: nil,
          permissions: nil,
          location: nil
        )
          super
        end

        def self.build(contract: StorageFileInfoContract.new, **)
          contract.call(**).to_monad.fmap { new(**_1.to_h) }
        end

        def clean_location
          return if location.nil?

          if location.starts_with? "/"
            CGI.unescape(location)
          else
            CGI.unescape("/#{location}")
          end
        end

        def self.from_id(file_id)
          new(id: file_id, status: "OK", status_code: 200)
        end
      end
    end
  end
end
