require "sidekiq"

module Sidekiq
  module Tasks
    class Job
      include Sidekiq::Job

      sidekiq_options Sidekiq::Tasks.config.sidekiq_options

      # @param name [String] The name of the task to execute.
      # @param args [Hash] The arguments to pass to the task.
      # @param dry_run [Boolean] Whether the task is executed in dry run mode.
      # @raise [Sidekiq::Tasks::TaskNotFoundError] If the task is not found.
      def perform(name, args, dry_run = false) # rubocop:disable Style/OptionalBooleanParameter -- Sidekiq args are positional
        symbolized_args = JSON.parse(args, symbolize_names: true)
        Sidekiq::Tasks.tasks.find_by!(name: name).execute(symbolized_args, jid: jid, dry_run: dry_run)
      end
    end
  end
end
