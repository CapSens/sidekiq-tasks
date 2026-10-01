module Sidekiq
  module Tasks
    module MagicComments
      module Handlers
        class Disable < Base
          def self.name_token
            "disable"
          end

          def self.cast(_raw_value)
            true
          end
        end
      end
    end
  end
end
