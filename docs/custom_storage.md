# Custom Storage Guide

This guide walks you through implementing a custom storage backend using ActiveRecord in a Rails application.

## Step 1: Generate the model and run the migration

```bash
rails generate model TaskExecution \
  task_name:string:index \
  jid:string:uniq \
  args:jsonb \
  enqueued_at:datetime \
  executed_at:datetime \
  finished_at:datetime \
  error:string \
  user:jsonb

rails db:migrate
```

## Step 2: Configure the initializer

In `config/initializers/sidekiq_tasks.rb`:

```ruby
class ActiveRecordStorage < Sidekiq::Tasks::Storage::Base
  def last_enqueue_at
    TaskExecution.where(task_name: task_name).order(enqueued_at: :desc).pick(:enqueued_at)
  end

  def history
    TaskExecution
      .where(task_name: task_name)
      .order(enqueued_at: :desc)
      .limit(history_limit)
      .select(:jid, :task_name, :args, :enqueued_at, :executed_at, :finished_at, :error, :user)
      .map(&:attributes)
  end

  def store_enqueue(jid, args, user: nil)
    TaskExecution.create_or_find_by!(jid: jid).update!(task_name: task_name, args: args, enqueued_at: Time.now, user: user)
  end

  def store_execution(jid, time_key)
    TaskExecution.create_or_find_by!(jid: jid).update!(time_key => Time.now)
  end

  def store_execution_error(jid, error)
    message = truncate_message("#{error.class}: #{error.message}", ERROR_MESSAGE_MAX_LENGTH)
    TaskExecution.create_or_find_by!(jid: jid).update!(error: message)
  end
end

Sidekiq::Tasks.configure do |config|
  config.storage = ActiveRecordStorage
end
```

> [!NOTE]
> The `history_limit` config is passed to each storage instance. The default Redis storage uses it to trim old entries. Custom storage implementations receive it via the `history_limit` accessor and can use it as needed (e.g. as a SQL `LIMIT`) or ignore it entirely.

## History entry format

The `history` method must return an array of hashes with the following keys:

| Key             | Type          | Description                          |
|-----------------|---------------|--------------------------------------|
| `"jid"`         | String        | The Sidekiq job ID                   |
| `"task_name"`   | String        | The task name                        |
| `"args"`        | Hash          | The arguments passed to the task     |
| `"enqueued_at"` | Time          | When the task was enqueued           |
| `"executed_at"` | Time \| nil   | When the task started executing      |
| `"finished_at"` | Time \| nil   | When the task finished executing     |
| `"error"`       | String \| nil | Error message if execution failed    |
| `"user"`        | Hash \| nil   | User who enqueued the task           |

Two optional keys are displayed when present:

| Key         | Type          | Description                                                  |
|-------------|---------------|--------------------------------------------------------------|
| `"dry_run"` | Boolean       | Whether the task was executed in dry run mode                |
| `"report"`  | Hash \| nil   | The execution report, see `Sidekiq::Tasks::Report#to_h`      |

They are stored through `store_dry_run(jid)` and `store_execution_report(jid, report)`, which do nothing by default.
Override them to support dry run badges and reports, e.g. with `dry_run:boolean` and `report:jsonb` columns, also added to the `history` select:

```ruby
def store_dry_run(jid)
  TaskExecution.create_or_find_by!(jid: jid).update!(dry_run: true)
end

def store_execution_report(jid, report)
  TaskExecution.create_or_find_by!(jid: jid).update!(report: report)
end
```

Reports are bounded by `config.report_max_bytes` (default: 64 KB, maximum: 1 MB). The 10 MB budget of the Redis storage for the reports of a task history does not apply to custom storages.

## Migrating from Redis

To keep the history, add this one-off task in `lib/tasks/sidekiq_tasks_copy_redis_history.rake`, run it once after switching to the custom storage with `bin/rails sidekiq_tasks:copy_redis_history`, then delete it:

```ruby
namespace :sidekiq_tasks do
  desc "Copy the sidekiq-tasks history from Redis to the database"
  task copy_redis_history: :environment do
    Sidekiq.redis { |conn| conn.keys("task:*:history") }.each do |history_key|
      task_name = history_key.delete_prefix("task:").delete_suffix(":history")

      Sidekiq::Tasks::Storage::Redis.new(task_name).history.each do |entry|
        TaskExecution.create_or_find_by!(jid: entry["jid"]).update!(entry.slice(*TaskExecution.column_names))
      end
    end
  end
end
```

Then clean up the old Redis history:

```bash
redis-cli --scan --pattern "task:*" | xargs redis-cli del
```

Or from a Rails console:

```ruby
Sidekiq.redis { |conn| conn.keys("task:*").each { |key| conn.del(key) } }
```
