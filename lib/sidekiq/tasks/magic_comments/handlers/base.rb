module Sidekiq
  module Tasks
    module MagicComments
      module Handlers
        class Base
          # Returns the magic comment token used after `sidekiq-tasks:`.
          #
          # @abstract Subclasses must implement this method.
          # @return [String]
          def self.name_token
            raise Sidekiq::Tasks::NotImplementedError, "Handler must implement .name_token"
          end

          # Casts the raw string value extracted from the magic comment into a typed value.
          #
          # @abstract Subclasses must implement this method.
          # @param raw_value [String, NilClass]
          # @return [Object]
          def self.cast(_raw_value)
            raise Sidekiq::Tasks::NotImplementedError, "Handler must implement .cast"
          end
        end
      end
    end
  end
end
