module Sidekiq
  module Tasks
    module SidekiqOptionsValidator
      KEYS = {
        queue: [String],
        retry: [NilClass, TrueClass, FalseClass, Integer],
        retry_for: [NilClass, Integer, Float],
        dead: [NilClass, TrueClass, FalseClass],
        backtrace: [NilClass, TrueClass, FalseClass, Integer],
        pool: [NilClass, String],
        tags: [NilClass, Array],
      }.freeze

      def self.validate!(options, allow_partial: false)
        Sidekiq::Tasks::Validations.validate_class!(options, [Hash], "sidekiq_options")

        KEYS.each do |key, classes|
          next if allow_partial && !options.key?(key)

          Sidekiq::Tasks::Validations.validate_class!(options[key], classes, key)
        end
      end
    end
  end
end
