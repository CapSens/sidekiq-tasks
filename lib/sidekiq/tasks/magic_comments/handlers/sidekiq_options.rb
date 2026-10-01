require "yaml"

module Sidekiq
  module Tasks
    module MagicComments
      module Handlers
        class SidekiqOptions < Base
          def self.name_token
            "sidekiq_options"
          end

          def self.cast(raw_value)
            return {} if raw_value.nil? || raw_value.strip.empty?

            options = parse_yaml(raw_value)
            # Unknown keys are passed as is to Sidekiq, for middleware options such as sidekiq-unique-jobs locks.
            Sidekiq::Tasks::SidekiqOptionsValidator.validate!(options, allow_partial: true)
            options
          end

          def self.parse_yaml(raw_value)
            YAML.safe_load("{#{raw_value}}", permitted_classes: [Symbol], symbolize_names: true)
          rescue Psych::SyntaxError => e
            raise Sidekiq::Tasks::ArgumentError,
                  "'sidekiq_options' magic comment is not valid YAML: #{e.message}"
          end
          private_class_method :parse_yaml
        end
      end
    end
  end
end
