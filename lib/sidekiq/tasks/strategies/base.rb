module Sidekiq
  module Tasks
    module Strategies
      class Base
        include Sidekiq::Tasks::Validations

        # A set of rules to fetch tasks.
        #
        # @return [Array<Sidekiq::Tasks::Strategies::Rules::Base>]
        # @see Sidekiq::Tasks::Strategies::Base#filtered_tasks
        attr_reader :rules

        # Initializes a strategy with the given rules.
        #
        # @param rules [Array<Sidekiq::Tasks::Strategies::Rules::Base>] List of rule instances to be applied.
        # @raise [Sidekiq::Tasks::ArgumentError] If the rules are not valid instances.
        def initialize(rules: [])
          @rules = rules

          validate_array_classes!(rules, [Sidekiq::Tasks::Strategies::Rules::Base], "rules")
        end

        # Returns the name of the strategy.
        #
        # @return [String] The name of the class without module namespaces.
        def name
          self.class.name.split("::").last
        end

        # Returns all the raw tasks that should be filtered.
        #
        # @abstract Subclasses must implement this method.
        # @return [Array] A list of tasks to be filtered.
        # @raise [NotImplementedError] If the method is not implemented in a subclass.
        def load_tasks
          raise NotImplementedError, "Strategy must implement #load_tasks"
        end

        # Executes a task with the given parameters.
        #
        # @note Consider accepting a `Sidekiq::Tasks::Task` instead of a task name.
        #
        # @param name [String] The name of the task to execute.
        # @param args [Hash, NilClass] Arguments to pass to the task.
        # @raise [NotImplementedError] If the method is not implemented in a subclass.
        def execute_task(_name, _args = nil)
          raise NotImplementedError, "Strategy must implement #execute_task"
        end

        # Enqueues a task with the given parameters and returns the JID.
        #
        # @param name [String] The name of the task to enqueue.
        # @param params [Hash] Parameters to pass to the task.
        # @param sidekiq_options [Hash] Per-task Sidekiq options that override class-level defaults.
        # @param dry_run [Boolean] Whether the task must be executed in dry run mode.
        # @return [String] The JID of the sidekiq job that will execute the task.
        def enqueue_task(name, params = {}, sidekiq_options: {}, dry_run: false)
          job = sidekiq_options.empty? ? Sidekiq::Tasks::Job : Sidekiq::Tasks::Job.set(sidekiq_options)
          job.perform_async(name, params.to_json, dry_run)
        end

        # Returns all the tasks that should be executed.
        #
        # @return [Array<Sidekiq::Tasks::Task>]
        def tasks
          filtered_tasks = load_tasks.select { |task| respects_rules?(task) }

          filtered_tasks.map { |task| Sidekiq::Tasks::Task.new(metadata: build_task_metadata(task), strategy: self) }
        end

        # Factory method to build the metadata for a task.
        #
        # @abstract Subclasses must implement this method.
        # @param task [Object] The task to build the metadata for.
        # @return [Sidekiq::Tasks::TaskMetadata] The metadata for the task.
        def build_task_metadata(_task)
          raise NotImplementedError, "Strategy must implement #build_task_metadata"
        end

        private

        # Checks if a task respects all the defined rules.
        #
        # @param task [Sidekiq::Tasks::Task] The task to validate against the rules.
        # @return [Boolean] `true` if the task respects all rules, `false` otherwise.
        def respects_rules?(task)
          rules.all? do |rule|
            rule.respected?(task)
          end
        end
      end
    end
  end
end
