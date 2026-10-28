module Sidekiq
  module Tasks
    module MagicComments
      module Handlers
        class DryRun < Base
          def self.name_token
            "dry_run"
          end

          def self.cast(_raw_value)
            true
          end
        end
      end
    end
  end
end
