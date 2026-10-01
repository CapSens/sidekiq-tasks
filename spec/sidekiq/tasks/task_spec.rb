require "spec_helper"

RSpec.describe Sidekiq::Tasks::Task do
  describe "validations" do
    it "accepts Sidekiq::Tasks::TaskMetadata as metadata", :aggregate_failures do
      expect(build_task(metadata: build_task_metadata).metadata).to be_a(Sidekiq::Tasks::TaskMetadata)

      expect { build_task(metadata: "foo") }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'metadata' must be an instance of Sidekiq::Tasks::TaskMetadata but received String"
        )
      )
    end

    it "accepts Sidekiq::Tasks::Strategies::Base as strategy", :aggregate_failures do
      expect(build_task(strategy: build_strategy).strategy).to be_a(Sidekiq::Tasks::Strategies::Base)

      expect { build_task(strategy: "foo") }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'strategy' must be an instance of Sidekiq::Tasks::Strategies::Base but received String"
        )
      )
    end
  end

  describe "#storage" do
    it "returns a memoized instance of the configured storage" do
      task = build_task(name: "foo:bar", args: ["bar"])
      storage = task.storage
      expect(storage).to be_a(Sidekiq::Tasks::Storage::Base)
      expect(storage).to be_a(Sidekiq::Tasks.config.storage)
      expect(storage.object_id).to eq(task.storage.object_id)
    end
  end

  describe "#last_enqueue_at" do
    it "returns the last enqueue at time from the storage", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["bar"])
      storage_last_enqueue_at = Time.new(2025, 1, 1, 12, 0, 0, "+00:00")
      storage = double(last_enqueue_at: storage_last_enqueue_at)
      expect(task).to receive(:storage).and_return(storage)
      expect(task.last_enqueue_at).to eq(storage_last_enqueue_at)
    end
  end

  describe "#history" do
    it "returns the history from the storage", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["bar"])

      storage_history = [
        {
          "jid" => "a1b2c3",
          "task_name" => "foo:bar",
          "args" => {"bar" => "baz"},
          "enqueued_at" => "2025-01-01 12:00:00 +0000",
        },
      ]

      storage = double(history: storage_history)
      expect(task).to receive(:storage).and_return(storage)
      expect(task.history).to eq(storage_history)
    end
  end

  describe "#enqueue" do
    before { clear_redis }

    it "enqueues the task through the strategy with params and stores the task trace" do
      current_time = Time.new(2025, 1, 1, 12, 0, 0, "+00:00")
      allow(Time).to receive(:now).and_return(current_time)

      task = build_task(name: "foo:bar", args: ["foo"])

      expect(task.strategy).to(
        receive(:enqueue_task)
          .with("foo:bar", {"foo" => "bar"}, sidekiq_options: {}, dry_run: false)
          .and_return("a1b2c3")
      )

      task.enqueue({"foo" => "bar"})

      aggregate_failures do
        expect(task.last_enqueue_at).to eq(current_time)
        expect(task.history.size).to eq(1)
        expect(task.history.first).to eq(
          {
            "jid" => "a1b2c3",
            "task_name" => "foo:bar",
            "args" => {"foo" => "bar"},
            "enqueued_at" => Time.at(current_time.to_f),
          }
        )
      end
    end

    it "passes user to storage when provided" do
      current_time = Time.new(2025, 1, 1, 12, 0, 0, "+00:00")
      allow(Time).to receive(:now).and_return(current_time)

      task = build_task(name: "foo:bar", args: ["foo"])
      user = {"id" => 1, "email" => "admin@example.com"}

      expect(task.strategy).to(
        receive(:enqueue_task)
          .with("foo:bar", {"foo" => "bar"}, sidekiq_options: {}, dry_run: false)
          .and_return("a1b2c3")
      )

      expect(task.storage).to(
        receive(:store_enqueue)
          .with("a1b2c3", {"foo" => "bar"}, user: user)
      )

      task.enqueue({"foo" => "bar"}, user: user)
    end

    it "does not include user when not provided" do
      task = build_task(name: "foo:bar", args: ["foo"])

      expect(task.strategy).to(
        receive(:enqueue_task)
          .with("foo:bar", {"foo" => "bar"}, sidekiq_options: {}, dry_run: false)
          .and_return("a1b2c3")
      )

      expect(task.storage).to(
        receive(:store_enqueue)
          .with("a1b2c3", {"foo" => "bar"}, user: nil)
      )

      task.enqueue({"foo" => "bar"})
    end

    it "forwards per-task sidekiq_options to the strategy" do
      task = build_task(name: "foo:bar", args: ["foo"], sidekiq_options: {queue: "critical", retry: 5})

      expect(task.strategy).to(
        receive(:enqueue_task)
          .with("foo:bar", {"foo" => "bar"}, sidekiq_options: {queue: "critical", retry: 5}, dry_run: false)
          .and_return("a1b2c3")
      )

      task.enqueue({"foo" => "bar"})
    end

    it "raises when the task is broken", :aggregate_failures do
      task = build_task(name: "foo:bar", error: "boom")

      expect(task.strategy).not_to receive(:enqueue_task)
      expect { task.enqueue }.to raise_error(
        Sidekiq::Tasks::ArgumentError,
        "cannot enqueue broken task 'foo:bar': boom"
      )
    end
  end

  describe "#enqueue in dry run mode" do
    it "enqueues the task in dry run mode and marks the history entry", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["foo"])

      expect(task.strategy).to receive(:enqueue_task).with("foo:bar", {"foo" => "bar"}, sidekiq_options: {}, dry_run: true).and_return("a1b2c3")
      expect(task.storage).to receive(:store_enqueue).with("a1b2c3", {"foo" => "bar"}, user: nil)
      expect(task.storage).to receive(:store_dry_run).with("a1b2c3")

      task.enqueue({"foo" => "bar"}, dry_run: true)
    end

    it "does not mark the history entry when dry run is disabled" do
      task = build_task(name: "foo:bar", args: ["foo"])

      allow(task.strategy).to receive(:enqueue_task).and_return("a1b2c3")
      allow(task.storage).to receive(:store_enqueue)
      expect(task.storage).not_to receive(:store_dry_run)

      task.enqueue({"foo" => "bar"})
    end
  end

  describe "#execute" do
    it "exposes the run to the task code", :aggregate_failures do
      task = build_task(name: "foo:bar")
      allow(task.storage).to receive(:store_execution)

      expect(task.strategy).to receive(:execute_task) do
        expect(Sidekiq::Tasks.current_run.dry_run?).to eq(true)
      end

      task.execute({}, jid: "a1b2c3", dry_run: true)

      expect(Thread.current[Sidekiq::Tasks::Run::THREAD_KEY]).to be_nil
    end

    it "stores the report before finished_at" do
      task = build_task(name: "foo:bar")

      allow(task.strategy).to receive(:execute_task) { Sidekiq::Tasks.current_run.report.increment(:success) }
      expect(task.storage).to receive(:store_execution).with("a1b2c3", "executed_at").ordered
      expect(task.storage).to(
        receive(:store_execution_report)
          .with("a1b2c3", {"values" => {"success" => 1}, "lists" => {}})
          .ordered
      )
      expect(task.storage).to receive(:store_execution).with("a1b2c3", "finished_at").ordered

      task.execute({}, jid: "a1b2c3")
    end

    it "stores the partial report when execution fails" do
      task = build_task(name: "foo:bar")

      allow(task.strategy).to receive(:execute_task) do
        Sidekiq::Tasks.current_run.report.increment(:success)
        raise "boom"
      end
      allow(task.storage).to receive(:store_execution)
      allow(task.storage).to receive(:store_execution_error)
      expect(task.storage).to receive(:store_execution_report).with("a1b2c3", {"values" => {"success" => 1}, "lists" => {}})

      expect { task.execute({}, jid: "a1b2c3") }.to raise_error("boom")
    end

    it "bounds the report with the storage report_max_bytes" do
      task = build_task(name: "foo:bar")

      allow(task.storage).to receive(:report_max_bytes).and_return(10)
      allow(task.strategy).to receive(:execute_task) { Sidekiq::Tasks.current_run.report[:message] = "too long for the limit" }
      allow(task.storage).to receive(:store_execution)
      expect(task.storage).to receive(:store_execution_report).with("a1b2c3", {"values" => {}, "lists" => {}, "truncated" => true})

      task.execute({}, jid: "a1b2c3")
    end

    it "does not store an empty report" do
      task = build_task(name: "foo:bar")

      allow(task.strategy).to receive(:execute_task)
      allow(task.storage).to receive(:store_execution)
      expect(task.storage).not_to receive(:store_execution_report)

      task.execute({}, jid: "a1b2c3")
    end

    it "executes the task through the strategy with params", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["foo"])
      expect(task.strategy).to receive(:execute_task).with("foo:bar", {foo: "bar"})

      task.execute({foo: "bar"})
    end

    it "stores the execution history with the given jid", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["foo"])

      expect(task.strategy).to receive(:execute_task).with("foo:bar", {foo: "bar"})
      expect(task.storage).to receive(:store_execution).with("a1b2c3", "executed_at")
      expect(task.storage).to receive(:store_execution).with("a1b2c3", "finished_at")

      task.execute({foo: "bar"}, jid: "a1b2c3")
    end

    it "stores the error and re-raises the exception when execution fails", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["foo"])
      error = StandardError.new("Something went wrong")

      expect(task.strategy).to receive(:execute_task).with("foo:bar", {foo: "bar"}).and_raise(error)
      expect(task.storage).to receive(:store_execution).with("a1b2c3", "executed_at")
      expect(task.storage).to receive(:store_execution_error).with("a1b2c3", error)
      expect(task.storage).to receive(:store_execution).with("a1b2c3", "finished_at")

      expect { task.execute({foo: "bar"}, jid: "a1b2c3") }.to raise_error(StandardError, "Something went wrong")
    end

    it "stores the error and re-raises when the task calls abort or exit", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["foo"])
      error = SystemExit.new

      expect(task.strategy).to receive(:execute_task).with("foo:bar", {foo: "bar"}).and_raise(error)
      expect(task.storage).to receive(:store_execution).with("a1b2c3", "executed_at")
      expect(task.storage).to receive(:store_execution_error).with("a1b2c3", error)
      expect(task.storage).to receive(:store_execution).with("a1b2c3", "finished_at")

      expect { task.execute({foo: "bar"}, jid: "a1b2c3") }.to raise_error(SystemExit)
    end
  end

  describe "#dry_run_supported?" do
    it "returns the dry_run metadata", :aggregate_failures do
      expect(build_task(dry_run: true).dry_run_supported?).to eq(true)
      expect(build_task.dry_run_supported?).to eq(false)
    end
  end
end
