require "sidekiq"

module Sidekiq
  module Tasks
    class Config
      DEFAULT_SIDEKIQ_OPTIONS = {
        queue: "default",
        retry: false,
      }.freeze

      DEFAULT_STRATEGIES = [
        Sidekiq::Tasks::Strategies::RakeTask.new(
          rules: [
            Sidekiq::Tasks::Strategies::Rules::TaskFromLib.new,
            Sidekiq::Tasks::Strategies::Rules::EnableWithComment.new,
          ]
        ),
      ].freeze

      DEFAULT_STORAGE = Sidekiq::Tasks::Storage::Redis

      DEFAULT_HISTORY_LIMIT = 10

      DEFAULT_REPORT_MAX_BYTES = 64 * 1024

      REPORT_MAX_BYTES_LIMIT = 1024 * 1024

      include Sidekiq::Tasks::Validations

      attr_reader :strategies, :sidekiq_options, :authorization, :history_limit, :current_user, :storage,
                  :report_max_bytes

      def initialize
        @sidekiq_options = DEFAULT_SIDEKIQ_OPTIONS
        @strategies = DEFAULT_STRATEGIES
        @storage = DEFAULT_STORAGE
        @authorization = ->(_env) { true }
        @history_limit = DEFAULT_HISTORY_LIMIT
        @current_user = nil
        @report_max_bytes = DEFAULT_REPORT_MAX_BYTES
      end

      # @see https://github.com/sidekiq/sidekiq/wiki/Advanced-Options#jobs
      def sidekiq_options=(options)
        Sidekiq::Tasks::SidekiqOptionsValidator.validate!(options)

        @sidekiq_options = options
      end

      def strategies=(strategies)
        validate_array_classes!(strategies, [Sidekiq::Tasks::Strategies::Base], "strategies")

        @strategies = strategies
      end

      def storage=(storage_class)
        validate_subclass!(storage_class, Sidekiq::Tasks::Storage::Base, "storage")

        @storage = storage_class
      end

      def history_limit=(limit)
        validate_class!(limit, [Integer], "history_limit")

        raise Sidekiq::Tasks::ArgumentError, "'history_limit' must be greater than 0" if limit <= 0

        @history_limit = limit
      end

      def report_max_bytes=(max_bytes)
        validate_class!(max_bytes, [Integer], "report_max_bytes")

        raise Sidekiq::Tasks::ArgumentError, "'report_max_bytes' must be greater than 0" if max_bytes <= 0

        @report_max_bytes = bounded(max_bytes, REPORT_MAX_BYTES_LIMIT, "report_max_bytes")
      end

      def authorization=(authorization_proc)
        validate_class!(authorization_proc, [Proc], "authorization")

        @authorization = authorization_proc
      end

      def current_user=(current_user_proc)
        validate_class!(current_user_proc, [Proc], "current_user")

        @current_user = current_user_proc
      end

      private

      # A too large value never prevents the application from starting: it is lowered to the limit.
      def bounded(value, limit, name)
        return value if value <= limit

        Sidekiq.logger.warn("[sidekiq-tasks] '#{name}' (#{value}) exceeds the maximum, using #{limit}")
        limit
      end
    end
  end
end
