module Sidekiq
  module Tasks
    module Strategies
      class RakeTask < Base
        def initialize(rules: [], scanner: Sidekiq::Tasks::MagicComments::Scanner.new)
          super(rules: rules)
          @scanner = scanner
        end

        def load_tasks
          Rake::TaskManager.record_task_metadata = true
          Rake.application.load_rakefile
          Rake::Task.tasks
        end

        def build_task_metadata(task)
          Sidekiq::Tasks::TaskMetadata.new(
            name: task.name,
            desc: task.full_comment,
            file: task_file(task),
            args: task.arg_names,
            **magic_comment_options(task)
          )
        rescue Sidekiq::Tasks::ArgumentError => e
          Sidekiq::Tasks::TaskMetadata.new(name: task.name, file: task_file(task), error: e.message)
        end

        def execute_task(name, args = nil)
          Rake::Task[name].execute(args)
        end

        private

        def task_file(task)
          task.locations.first&.split(":")&.first
        end

        def magic_comment_options(task)
          comments = @scanner.scan(task)
          handlers = Sidekiq::Tasks::MagicComments::Handlers

          {
            sidekiq_options: comments.fetch(handlers::SidekiqOptions.name_token, default: {}),
            dry_run: comments.any?(handlers::DryRun.name_token),
          }
        end
      end
    end
  end
end
