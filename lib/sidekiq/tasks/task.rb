require "forwardable"

module Sidekiq
  module Tasks
    class Task
      extend Forwardable
      include Sidekiq::Tasks::Validations

      def_delegators :metadata, :name, :desc, :file, :args, :sidekiq_options, :error, :error?
      def_delegators :storage, :last_enqueue_at, :history
      def_delegator :metadata, :dry_run?, :dry_run_supported?

      attr_reader :metadata, :strategy

      # @param metadata [Sidekiq::Tasks::TaskMetadata] The metadata for the task.
      # @param strategy [Sidekiq::Tasks::Strategies::Base] The strategy to use to execute the task.
      # @raise [Sidekiq::Tasks::ArgumentError] If the metadata or strategy are not valid instances.
      def initialize(metadata:, strategy:)
        @metadata = metadata
        @strategy = strategy

        validate_class!(metadata, [Sidekiq::Tasks::TaskMetadata], "metadata")
        validate_class!(strategy, [Sidekiq::Tasks::Strategies::Base], "strategy")
      end

      def enqueue(params = {}, user: nil, dry_run: false)
        raise Sidekiq::Tasks::ArgumentError, "cannot enqueue broken task '#{name}': #{error}" if error?

        enqueue_options = {}
        enqueue_options[:sidekiq_options] = sidekiq_options if sidekiq_options.any?
        enqueue_options[:dry_run] = true if dry_run

        jid = strategy.enqueue_task(name, params, **enqueue_options)

        storage.store_enqueue(jid, params, user: user)
        storage.store_dry_run(jid) if dry_run
      end

      def execute(params = {}, jid: nil, dry_run: false)
        run = Sidekiq::Tasks::Run.new(dry_run: dry_run, report_max_bytes: storage.report_max_bytes)
        storage.store_execution(jid, "executed_at")

        begin
          Sidekiq::Tasks::Run.with(run) { strategy.execute_task(name, params) }
        rescue StandardError, SystemExit => e
          finish_execution(jid, run)
          storage.store_execution_error(jid, e)
          raise
        end

        finish_execution(jid, run)
      end

      def storage
        @_storage ||= Sidekiq::Tasks.config.storage.new(name, history_limit: Sidekiq::Tasks.config.history_limit)
      end

      private

      # The report is stored before finished_at so that it is displayed as soon as the execution appears finished.
      def finish_execution(jid, run)
        storage.store_execution_report(jid, run.report.to_h) unless run.report.empty?
        storage.store_execution(jid, "finished_at")
      end
    end
  end
end
