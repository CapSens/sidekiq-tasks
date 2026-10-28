## Changelog

### [Unreleased]

- Add per-task `sidekiq_options` magic comment to override the global options at enqueue time, displayed on the task detail page.
- Render tasks with an invalid magic comment as a broken state in the web UI instead of crashing the tasks list.
- Validate the values of the supported keys of the `sidekiq_options` magic comment, other keys are passed as is to Sidekiq.
- Add dry run mode: tasks with the `sidekiq-tasks:dry_run` magic comment get a "Dry run" checkbox, checked by default, and read it with `Sidekiq::Tasks.dry_run?`.
- Add structured execution reports (`Sidekiq::Tasks.report`) displayed in the task history.
- Add a configurable `report_max_bytes` option (default: 64 KB, maximum: 1 MB) bounding the report size. The Redis storage also keeps the reports of a task history within 10 MB.
- Fix detection of stacked magic comments placed before a `desc` or a `namespace`.
- Fix magic comments leaking to a neighbour task or a similarly named namespace, and support nested namespaces.
- Escape task arguments, enqueuing user and error message in the task history.
- Fix execution times lost in the history when the job starts before the history entry is stored.

### [1.1.1] - 2026-04-12

- Transfer repository ownership to Capsens organization.

### [1.1.0] - 2026-04-08

- Search tasks by description in addition to name.

### [1.0.1] - 2026-03-17

- Fix magic comment detection for tasks with multiline descriptions (heredoc, multiline strings, backslash continuation).

### [1.0.0] - 2026-03-13

- Add configurable `storage` option with support for custom backends (default: Redis).
- Add configurable `current_user` option to track who enqueued each task.
- Add configurable `history_limit` option (default: 10).
- Add sortable columns (`name`, `last_enqueued`) in the tasks list.

### [0.1.8] - 2026-03-06

- Replace deprecated `webdrivers` gem with `selenium-webdriver`.
- Avoid duplicate CI runs on pull request branches.
- Fix `retry` option validation to accept integer values.
- Add `retry_for` option support (Sidekiq 7.1.3+).
- Fix `find_by` to use exact name matching instead of fuzzy matching.
- Disable live poll on tasks pages to prevent form state loss (Sidekiq >= 7.0.1).
- Escape filter parameter in tasks view to prevent HTML injection.

### [0.1.7] - 2025-07-27

- Support multiline description in task view.
- Add authorization support for web interface access.

### [0.1.6] - 2025-05-11

- Enable CI workflows on all branches. (#4)
- Add description to task list. (#2)
- Detect magic comment before multiline desc. (#3)
- Fix style tag rendering and plugin registration for Sidekiq Web UI 7.3+ and 8.0+. (#1)
- Enable horizontal scroll on tasks table for mobile. (#5)

### [0.1.5] - 2025-05-04

- Add duration, status and error reports to history.
- Fix Code Climate report by updating CI runner from `ubuntu-20.04` to `ubuntu-22.04`.

### [0.1.4] - 2025-03-23

- Fix gem load error by moving the entrypoint to the correct path.
- Support enabling/disabling all tasks in a namespace with a magic comment.
- Improve task search to allow more flexible and intuitive matching.
- Fix deprecation warning by avoiding direct access to `params` (Sidekiq 8 compatibility).

### [0.1.3] - 2025-03-22

- Change required Ruby version to 3.0.0.
- Add `DisableWithComment` rule to disable a specific task with a magic comment.

### [0.1.2] - 2025-03-22

- Update plugin registration for Sidekiq 7.3+ compatibility.

### [0.1.1] - 2025-02-25

- Add an environment confirmation input to the task enqueuing form.

### [0.1.0] - 2025-02-23

- Initial release.
