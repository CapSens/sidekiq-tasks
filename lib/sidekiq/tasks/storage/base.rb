module Sidekiq
  module Tasks
    module Storage
      class Base
        ERROR_MESSAGE_MAX_LENGTH = 255

        attr_reader :task_name, :history_limit

        def initialize(task_name, history_limit: nil)
          @task_name = task_name
          @history_limit = history_limit
        end

        # Returns the last enqueue time for the task.
        #
        # @abstract Subclasses must implement this method.
        # @return [Time, NilClass] The last enqueue time or nil.
        # @raise [NotImplementedError] If the method is not implemented in a subclass.
        def last_enqueue_at
          raise NotImplementedError, "Storage must implement #last_enqueue_at"
        end

        # Returns the execution history for the task.
        #
        # @abstract Subclasses must implement this method.
        # @return [Array<Hash>] The execution history entries.
        # @raise [NotImplementedError] If the method is not implemented in a subclass.
        def history
          raise NotImplementedError, "Storage must implement #history"
        end

        # Stores enqueue information for the task.
        #
        # @abstract Subclasses must implement this method.
        # @param jid [String] The Sidekiq job ID.
        # @param args [Hash] The arguments passed to the task.
        # @param user [Hash, NilClass] The user who enqueued the task.
        # @raise [NotImplementedError] If the method is not implemented in a subclass.
        def store_enqueue(_jid, _args, user: nil)
          raise NotImplementedError, "Storage must implement #store_enqueue"
        end

        # Stores execution time for a specific history entry.
        #
        # @abstract Subclasses must implement this method.
        # @param jid [String] The Sidekiq job ID.
        # @param time_key [String] The time key to store (e.g. "executed_at", "finished_at").
        # @raise [NotImplementedError] If the method is not implemented in a subclass.
        def store_execution(_jid, _time_key)
          raise NotImplementedError, "Storage must implement #store_execution"
        end

        # Stores an execution error for a specific history entry.
        #
        # @abstract Subclasses must implement this method.
        # @param jid [String] The Sidekiq job ID.
        # @param error [Exception] The error that occurred during execution.
        # @raise [NotImplementedError] If the method is not implemented in a subclass.
        def store_execution_error(_jid, _error)
          raise NotImplementedError, "Storage must implement #store_execution_error"
        end

        # Marks a history entry as a dry run.
        # Optional: storages that don't implement it simply don't display the dry run badge.
        #
        # @param jid [String] The Sidekiq job ID.
        def store_dry_run(_jid)
        end

        # Stores the execution report for a specific history entry.
        # Optional: storages that don't implement it simply don't display reports.
        #
        # @param jid [String] The Sidekiq job ID.
        # @param report [Hash] The report, see Sidekiq::Tasks::Report#to_h.
        def store_execution_report(_jid, _report)
        end

        # The maximum size of a stored report, lowered by storages with their own memory constraints.
        #
        # @return [Integer]
        def report_max_bytes
          Sidekiq::Tasks.config.report_max_bytes
        end

        protected

        def truncate_message(message, max_length)
          return message if message.length <= max_length

          "#{message[0...(max_length - 3)]}..."
        end
      end
    end
  end
end
