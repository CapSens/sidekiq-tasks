# Sidekiq::Tasks

[![CI Status](https://github.com/CapSens/sidekiq-tasks/actions/workflows/ci.yml/badge.svg)](https://github.com/CapSens/sidekiq-tasks/actions/workflows/ci.yml)
[![Maintainability](https://qlty.sh/gh/CapSens/projects/sidekiq-tasks/maintainability.svg)](https://qlty.sh/gh/CapSens/projects/sidekiq-tasks)
[![Code Coverage](https://qlty.sh/gh/CapSens/projects/sidekiq-tasks/coverage.svg)](https://qlty.sh/gh/CapSens/projects/sidekiq-tasks)

> A [Sidekiq](https://github.com/sidekiq/sidekiq) extension for task management.

Sidekiq-Tasks extends Sidekiq by providing an interface to enqueue tasks directly from the web interface. By default it works with Rake tasks but it can be easily extended to support other task execution systems.

![Task view](docs/task.png)

## Requirements

- Ruby >= 3.0
- Sidekiq >= 6.5 (compatible with 6.5, 7.x, and 8.x)

## Installation

```bash
bundle add sidekiq-tasks
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install sidekiq-tasks
```

Add the following to your `config/routes.rb` file:

```ruby
require "sidekiq/web"
require "sidekiq/tasks/web"
```

Now you can access the web interface at `/sidekiq/tasks` and you'll see a list of all the available tasks.
Once you've found your task, you can access the task details page to see the metadata, history and form to enqueue the task.

## Prerequisites

Sidekiq Tasks is based on the concept of **strategies** and **rules** to manage **tasks**.

- A **task** represents a unit of work that can be enqueued and executed.
- A **strategy** defines how tasks are loaded, built, enqueued, and executed.
- A **rule** is a condition given to a strategy to determine which tasks are available.

## Default strategy

By default, it comes with the `Sidekiq::Tasks::Strategies::RakeTask` strategy, which allows you to enqueue and execute Rake tasks with their arguments.

### Rules

In accordance with the principle of least privilege, it has the following rules:
  - **`TaskFromLib`** Only tasks from the `lib` folder are loaded.
  - **`EnableWithComment`** Only tasks explicitly enabled with a magic comment are loaded.

Example of an enabled task in `lib/tasks/my_task.rake`:

```ruby
# sidekiq-tasks:enable
task :my_task do
  puts "my_task"
end
```

Enable all tasks within a namespace:

```ruby
# sidekiq-tasks:enable
namespace :my_namespace do
  task :my_task do
    puts "my_task"
  end

  task :another_task do
    puts "another_task"
  end
end
```

You can also use `DisableWithComment` rule to selectively **disable** tasks. (see [strategies configuration](#strategies-configuration))
It works similarly to `EnableWithComment`, but with inverted logic. Example of a disabled task:

```ruby
# sidekiq-tasks:disable
task :my_task do
  puts "my_task"
end
```

### Arguments

Task arguments are automatically detected and made available in the form. For example, if you have a task defined like this:

```ruby
task :my_task, [:arg1, :arg2] => :environment do |_, args|
  puts "arg1: #{args[:arg1]}, arg2: #{args[:arg2]}"
end
```

You will see a form with two input fields for `arg1` and `arg2` when you access the task details page.

> [!IMPORTANT]
> The arguments are passed as strings, so you may need to convert them to the appropriate type in your task implementation.

## Strategies configuration

Strategies can be configured through the `config.strategies` option.
For example if you want to enable all tasks in the lib folder and disable a few specific ones manually:

```ruby
Sidekiq::Tasks.configure do |config|
  config.strategies = [
    Sidekiq::Tasks::Strategies::RakeTask.new(
      rules: [
        Sidekiq::Tasks::Strategies::Rules::TaskFromLib.new,
        Sidekiq::Tasks::Strategies::Rules::DisableWithComment.new,
      ]
    )
  ]
end
```

You can also define your own strategy creating a subclass of `Sidekiq::Tasks::Strategies::Base`.

Each strategy must implement the following methods:

  - `load_tasks`: Returns all the raw tasks that should be filtered.
  - `build_task_metadata`: Build metadata for a task.
  - `execute_task`: Execute a task.

A strategy has a `tasks` method that filters the loaded tasks according to the rules and builds `Sidekiq::Tasks::Task` instances with `build_task_metadata` for each raw task.

**Example:**

Here is an example of a strategy that loads tasks from a YAML configuration file, builds metadata and executes them as system commands:

```ruby
class ScriptStrategy < Sidekiq::Tasks::Strategies::Base
  def load_tasks
    YAML.load_file("config/scripts.yml")
  end

  def build_task_metadata(task)
    Sidekiq::Tasks::TaskMetadata.new(
      name: task["name"],
      desc: task["desc"],
      args: task["args"],
      file: task["file"]
    )
  end

  def execute_task(name, args = {})
    system "ruby #{name} #{args.values.join(" ")}"
  end
end

Sidekiq::Tasks.configure do |config|
  config.strategies = [ScriptStrategy.new]
end
```

> [!CAUTION]
> This is an example, executing tasks via system exposes your application to command injection risks.
> Never execute user input directly without strict validation.

## Strategy rules

Strategies can use rules to determine which tasks should be loaded.
Rules must inherit from `Sidekiq::Tasks::Strategies::Rules::Base` and implement the `respected?` method.
Here is an example of a rule that filters only scripts that match 'foo' in their filename:

```ruby
class FileMatchesFoo < Sidekiq::Tasks::Strategies::Rules::Base
  def respected?(task)
    task["file"].match?(/foo/)
  end
end

Sidekiq::Tasks.configure do |config|
  config.strategies = [ScriptStrategy.new(rules: [FileMatchesFoo.new])]
end
```

## Strategy enqueuing

By default, strategies enqueue tasks using the `Sidekiq::Tasks::Job` class.
You can configure `sidekiq_options` as follows:

```ruby
Sidekiq::Tasks.configure do |config|
  # Default options are {queue: "default", retry: false}
  config.sidekiq_options = {queue: "low", retry: false}
end
```

All standard [Sidekiq job options](https://github.com/sidekiq/sidekiq/wiki/Advanced-Options#jobs) are supported.

### Per-task overrides via magic comment

You can override `sidekiq_options` for a single Rake task with the `sidekiq-tasks:sidekiq_options` magic comment placed right before the task:

```ruby
# sidekiq-tasks:enable
# sidekiq-tasks:sidekiq_options: queue: low
task :generate_sales_report do
  # ...
end
```

Placed before a namespace, it applies to all its tasks, and a task level comment takes precedence.

The value is parsed as inline YAML and merged on top of the global `config.sidekiq_options` at enqueue time. Supported keys: `queue`, `retry`, `retry_for`, `dead`, `backtrace`, `pool`, `tags`.
These keys are validated: an invalid value (e.g. `retry: abc`) displays the task as broken in the web interface, and it cannot be enqueued. Other keys are passed as is to Sidekiq, e.g. middleware options such as sidekiq-unique-jobs `lock: until_executed`.

You can also override the `enqueue_task` method to implement your own enqueuing logic for your strategy:

```ruby
class ScriptStrategy < Sidekiq::Tasks::Strategies::Base
  def enqueue_task(name, params = {})
    ScriptJob.perform_async(name, params)
  end
end
```

> [!WARNING]
> Ensure that `enqueue_task` returns the JID of the Sidekiq job that will execute the task.

## Authorization

By default, web interface access is not restricted. You can configure authorization to restrict access to the tasks :

```ruby
Sidekiq::Tasks.configure do |config|
  config.authorization = ->(env) do
    env["warden"].user(:admin_user).super_admin?
  end
end
```

>[!NOTE]
> The `Tasks` button in the header will still be displayed regardless of the value of `authorization`.

## Execution history

Each task keeps a history of its last executions (default: 10, stored in Redis). The task detail page displays for each execution:

- The enqueue, start, and finish timestamps
- The arguments passed
- The error message if the execution failed

You can configure the history limit:

```ruby
Sidekiq::Tasks.configure do |config|
  config.history_limit = 25
end
```

You can also use a custom storage backend. See the [Custom Storage Guide](docs/custom_storage.md) for more details.

## Dry run and reports

Inside a task, `Sidekiq::Tasks.dry_run?` tells whether the task runs in dry run mode and `Sidekiq::Tasks.report` gives access to a structured report:

```ruby
# sidekiq-tasks:enable
# sidekiq-tasks:dry_run
task :sync_users => :environment do
  User.find_each do |user|
    Sync.call(user) unless Sidekiq::Tasks.dry_run?
    Sidekiq::Tasks.report.increment(:success)
  rescue => e
    Sidekiq::Tasks.report.increment(:errors)
    Sidekiq::Tasks.report.add(:failed, id: user.id, email: user.email, error: e.message)
  end
end
```

Both are shortcuts for `Sidekiq::Tasks.current_run.dry_run?` and `Sidekiq::Tasks.current_run.report`.

### Dry run

Dry run mode lets a user check what a task would do before running it for real, typically together with a [report](#report) of the rows it would process.

**What the gem does:**

- detects tasks declaring the `sidekiq-tasks:dry_run` magic comment. Like `enable`, it can be placed before the task, its `desc` or its `namespace`, stacked with other magic comments,
- displays a **Dry run** checkbox on these tasks, checked by default: the user has to uncheck it to execute the task for real. Other tasks display a warning stating that they will be executed for real,
- passes the choice to the Sidekiq job, where `Sidekiq::Tasks.dry_run?` returns it,
- flags dry runs with a badge in the task history.

**What the developer does:**

- adds the `sidekiq-tasks:dry_run` magic comment to the tasks that support dry run mode,
- skips every side effect when `Sidekiq::Tasks.dry_run?` is `true`: database writes, emails, API calls, file uploads, enqueued jobs...,
- keeps the rest of the task running (queries, validations, computations), so that the dry run reflects what the real run would do,
- optionally fills the report, so that the dry run result shows up in the web interface.

> [!WARNING]
> The gem never skips anything by itself: a task declaring the magic comment without checking `Sidekiq::Tasks.dry_run?` executes all of its side effects, even when the checkbox is checked.

Outside of the web interface (e.g. `rake sync_users` in a terminal), `dry_run?` is `false`.
Both `dry_run?` and `report` are optional: a task can use the report without dry run mode, and existing tasks keep working unchanged.

### Report

- `report[:key] = value` sets a summary value.
- `report.increment(:key)` increments a counter.
- `report.add(:key, item)` adds an item (a scalar or a flat Hash) to a list. Hash items are displayed as a table whose columns are the hash keys.

Keys are free: use as many lists as needed (`:synced`, `:skipped`, `:failed`...). Values are displayed in the history table, lists in a collapsible section below it (the latest execution is expanded). The report is stored whether the task runs in dry run mode or not, and also when it fails.

Numbers, booleans and `nil` are kept as is, other values are converted to strings: pass the useful attributes of an object (`{id: user.id, email: user.email}`) rather than the object itself, and prefer one list per key to nested structures.

The report is stored with the execution history, so its size is bounded by `report_max_bytes` (default: 64 KB, maximum: 1 MB):

```ruby
Sidekiq::Tasks.configure do |config|
  config.report_max_bytes = 256 * 1024
end
```

- a value above the maximum does not prevent the application from starting: it is lowered to the maximum and a warning is logged,
- when the report exceeds it, the last items of the longest lists are dropped and the report is flagged as truncated in the web interface, the counts remain exact,
- with the Redis storage, the reports of a task history never exceed 10 MB: with a large `history_limit`, the size of each report is lowered accordingly (`10 MB / history_limit`),
- strings are truncated to 255 characters, so that a single long message does not fill the whole report,
- at most 50 values, 50 lists and 50 keys per item, guarding against keys built from the data,
- while the task runs, items stop being kept beyond 4 times the report size, so that the worker memory stays bounded.

The report never makes a task fail. Outside of a Sidekiq::Tasks job, it is printed as JSON when the process exits.

> [!TIP]
> For large or complex reports, prefer a database storage (see the [Custom Storage Guide](docs/custom_storage.md)) over Redis: reports are kept in the database instead of Redis memory, and are not lowered by the 10 MB budget of the Redis storage.

> [!NOTE]
> Custom strategies enable dry run mode by building their metadata with `dry_run: true`.
> Those overriding `enqueue_task` then receive a `dry_run: true` keyword argument, to pass to `Sidekiq::Tasks::Job` as its third argument.
> Custom storages display the dry run badge and reports by implementing `store_dry_run` and `store_execution_report`, see the [Custom Storage Guide](docs/custom_storage.md).

## Current user

You can configure a `current_user` proc to track who enqueued each task.
The proc receives the Rack `env` and should return a Hash identifying the user:

```ruby
Sidekiq::Tasks.configure do |config|
  config.current_user = ->(env) do
    user = env["warden"].user(:admin_user)
    {id: user.id, email: user.email}
  end
end
```

When configured, an "Enqueued by" column appears in the task history table.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/CapSens/sidekiq-tasks. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/CapSens/sidekiq-tasks/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Sidekiq::Tasks project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/CapSens/sidekiq-tasks/blob/master/CODE_OF_CONDUCT.md).
