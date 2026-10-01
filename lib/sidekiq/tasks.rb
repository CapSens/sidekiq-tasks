# frozen_string_literal: true

require "rake"

require_relative "tasks/errors"
require_relative "tasks/validations"
require_relative "tasks/sidekiq_options_validator"
require_relative "tasks/magic_comments"
require_relative "tasks/storage"
require_relative "tasks/strategies"
require_relative "tasks/version"

module Sidekiq
  module Tasks
    autoload :Config, "sidekiq/tasks/config"
    autoload :Job, "sidekiq/tasks/job"
    autoload :Report, "sidekiq/tasks/run"
    autoload :Run, "sidekiq/tasks/run"
    autoload :Set, "sidekiq/tasks/set"
    autoload :Task, "sidekiq/tasks/task"
    autoload :TaskMetadata, "sidekiq/tasks/task_metadata"

    class << self
      def configure
        yield(config)
      end

      def config
        @_config ||= Sidekiq::Tasks::Config.new
      end

      def strategies
        @_strategies ||= Sidekiq::Tasks::Set.new(config.strategies)
      end

      def tasks
        @_tasks ||= Sidekiq::Tasks::Set.new(strategies.flat_map(&:tasks))
      end

      # @return [Sidekiq::Tasks::Run] The run of the task being executed, see Sidekiq::Tasks::Run.current.
      def current_run
        Sidekiq::Tasks::Run.current
      end

      def dry_run?
        current_run.dry_run?
      end

      def report
        current_run.report
      end
    end
  end
end
