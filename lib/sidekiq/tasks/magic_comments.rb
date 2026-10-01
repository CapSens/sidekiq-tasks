module Sidekiq
  module Tasks
    module MagicComments
      autoload :Comment, "sidekiq/tasks/magic_comments/comment"
      autoload :Comments, "sidekiq/tasks/magic_comments/comments"
      autoload :Registry, "sidekiq/tasks/magic_comments/registry"
      autoload :Scanner, "sidekiq/tasks/magic_comments/scanner"

      module Handlers
        autoload :Base, "sidekiq/tasks/magic_comments/handlers/base"
        autoload :Enable, "sidekiq/tasks/magic_comments/handlers/enable"
        autoload :Disable, "sidekiq/tasks/magic_comments/handlers/disable"
        autoload :DryRun, "sidekiq/tasks/magic_comments/handlers/dry_run"
        autoload :SidekiqOptions, "sidekiq/tasks/magic_comments/handlers/sidekiq_options"
      end
    end
  end
end

require_relative "magic_comments/registration"
