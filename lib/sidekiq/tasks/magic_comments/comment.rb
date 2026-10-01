module Sidekiq
  module Tasks
    module MagicComments
      class Comment
        VALID_LOCATIONS = %i[task desc namespace].freeze

        attr_reader :name, :raw_value, :location

        def initialize(name:, location:, raw_value: nil)
          @name = name.to_s
          @raw_value = raw_value
          @location = location

          validate!
        end

        private

        def validate!
          return if VALID_LOCATIONS.include?(location)

          raise Sidekiq::Tasks::ArgumentError,
                "'location' must be one of #{VALID_LOCATIONS.inspect} but received #{location.inspect}"
        end
      end
    end
  end
end
