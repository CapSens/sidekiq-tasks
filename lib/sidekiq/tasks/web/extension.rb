require "sidekiq/tasks/web/helpers/application_helper"
require "sidekiq/tasks/web/helpers/tag_helper"
require "sidekiq/tasks/web/helpers/task_helper"
require "sidekiq/tasks/web/helpers/pagination_helper"
require "sidekiq/tasks/web/helpers/sort_helper"
require "sidekiq/tasks/web/search"
require "sidekiq/tasks/web/pagination"
require "sidekiq/tasks/web/params"

module Sidekiq
  module Tasks
    module Web
      class Extension
        def self.registered(app)
          app.helpers(Sidekiq::Tasks::Web::Helpers::ApplicationHelper)
          app.helpers(Sidekiq::Tasks::Web::Helpers::TagHelper)
          app.helpers(Sidekiq::Tasks::Web::Helpers::TaskHelper)
          app.helpers(Sidekiq::Tasks::Web::Helpers::PaginationHelper)
          app.helpers(Sidekiq::Tasks::Web::Helpers::SortHelper)

          app.get "/tasks" do
            authorize!

            @search = Sidekiq::Tasks::Web::Search.new(fetch_params(:count, :page, :filter, :sort, :direction))

            erb(read_view(:tasks), locals: {search: @search})
          end

          app.get "/tasks/:name" do
            authorize!

            @task = find_task!(env["rack.route_params"][:name])

            history = @task.history
            per_page = 10
            page = [fetch_param("page").to_i, 1].max
            total_pages = [(history.size.to_f / per_page).ceil, 1].max
            history_entries = history.slice((page - 1) * per_page, per_page) || []

            erb(
              read_view(:task),
              locals: {
                task: @task,
                history_entries: history_entries,
                history_page: page,
                history_total_pages: total_pages,
                history_total_count: history.size,
              }
            )
          rescue Sidekiq::Tasks::NotFoundError
            throw :halt, [404, {Rack::CONTENT_TYPE => "text/plain"}, ["Task not found"]]
          end

          app.post "/tasks/:name/enqueue" do
            authorize!

            if fetch_param("env_confirmation") != current_env
              throw :halt, [400, {Rack::CONTENT_TYPE => "text/plain"}, ["Invalid confirm"]]
            end

            task = find_task!(env["rack.route_params"][:name])
            args = Sidekiq::Tasks::Web::Params.new(task, fetch_param("args")).permit!

            current_user = Sidekiq::Tasks.config.current_user&.call(env)
            dry_run = task.dry_run_supported? && fetch_param("dry_run") == "1"
            task.enqueue(args, user: current_user, dry_run: dry_run)

            redirect(task_url(root_path, task))
          rescue Sidekiq::Tasks::ArgumentError => e
            throw :halt, [400, {Rack::CONTENT_TYPE => "text/plain"}, [e.message]]
          rescue Sidekiq::Tasks::NotFoundError
            throw :halt, [404, {Rack::CONTENT_TYPE => "text/plain"}, ["Task not found"]]
          end
        end
      end
    end
  end
end
