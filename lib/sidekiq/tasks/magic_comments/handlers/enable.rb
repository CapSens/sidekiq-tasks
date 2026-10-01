module Sidekiq
  module Tasks
    module MagicComments
      module Handlers
        class Enable < Base
          def self.name_token
            "enable"
          end

          def self.cast(_raw_value)
            true
          end
        end
      end
    end
  end
end
