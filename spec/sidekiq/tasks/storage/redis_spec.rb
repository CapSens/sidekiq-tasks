require "spec_helper"

RSpec.describe Sidekiq::Tasks::Storage::Redis do
  describe "#jid_key" do
    it "returns the task name with the prefix" do
      expect(described_class.new("foo").jid_key).to eq("task:foo")
      expect(described_class.new("foo:bar").jid_key).to eq("task:foo:bar")
    end
  end

  describe "#history_key" do
    it "returns the history key with the jid key as prefix", :aggregate_failures do
      expect(described_class.new("foo").history_key).to eq("task:foo:history")
      expect(described_class.new("foo:bar").history_key).to eq("task:foo:bar:history")
    end
  end

  describe "#last_enqueue_at" do
    it "returns nil when the last enqueue at key is not found", :aggregate_failures do
      expect(Sidekiq).to receive(:redis).and_yield(double(hget: nil))
      expect(described_class.new("foo:bar").last_enqueue_at).to be_nil
    end

    it "returns the formatted last enqueue at time when present", :aggregate_failures do
      time = Time.new(2025, 1, 1, 12, 0, 0, "+00:00")
      expect(Sidekiq).to receive(:redis).and_yield(double(hget: time.to_f.to_s))
      expect(described_class.new("foo:bar").last_enqueue_at).to eq(time)
    end
  end

  describe "#history" do
    it "returns an empty array when the history is empty" do
      allow(Sidekiq).to receive(:redis).and_yield(double(lrange: [], ltrim: []))
      expect(described_class.new("foo:bar").history).to eq([])
    end

    it "returns the history, with parsed times, when present" do
      first_task_trace = {
        jid: "foo",
        task_name: "foo",
        args: {"bar" => "baz"},
        enqueued_at: Time.new(2025, 1, 1, 13, 0, 0, "+00:00").to_f,
      }

      second_task_trace = {
        jid: "bar",
        task_name: "bar",
        args: {"baz" => "qux"},
        enqueued_at: Time.new(2025, 1, 1, 12, 0, 0, "+00:00").to_f,
      }

      tasks_history = [first_task_trace, second_task_trace].map { |task_trace| Sidekiq.dump_json(task_trace) }
      allow(Sidekiq).to receive(:redis).and_yield(double(lrange: tasks_history, ltrim: []))

      expect(described_class.new("foo:bar").history).to eq(
        [
          {
            "jid" => "foo",
            "task_name" => "foo",
            "args" => {"bar" => "baz"},
            "enqueued_at" => Time.at(first_task_trace[:enqueued_at]),
          },
          {
            "jid" => "bar",
            "task_name" => "bar",
            "args" => {"baz" => "qux"},
            "enqueued_at" => Time.at(second_task_trace[:enqueued_at]),
          },
        ]
      )
    end
  end

  describe "#store_history" do
    before { clear_redis }

    let(:storage) { described_class.new("foo:bar", history_limit: 3) }

    it "stores the task history" do
      current_time = Time.now
      storage.store_history("a1b2c3", {"bar" => "baz"}, current_time)

      expect(storage.history).to eq(
        [
          {
            "jid" => "a1b2c3",
            "task_name" => "foo:bar",
            "args" => {"bar" => "baz"},
            "enqueued_at" => Time.at(current_time.to_f),
          },
        ]
      )
    end

    it "stores user when provided" do
      current_time = Time.now
      user = {"id" => 1, "email" => "admin@example.com"}
      storage.store_history("a1b2c3", {"bar" => "baz"}, current_time, user: user)

      expect(storage.history).to eq(
        [
          {
            "jid" => "a1b2c3",
            "task_name" => "foo:bar",
            "args" => {"bar" => "baz"},
            "enqueued_at" => Time.at(current_time.to_f),
            "user" => {"id" => 1, "email" => "admin@example.com"},
          },
        ]
      )
    end

    it "does not include user when nil" do
      current_time = Time.now
      storage.store_history("a1b2c3", {"bar" => "baz"}, current_time)

      expect(storage.history.first).not_to have_key("user")
    end

    it "trims the history to the configured history limit", :aggregate_failures do
      current_time = Time.now

      Sidekiq.redis do |conn|
        storage.history_limit.times do |index|
          task_trace = Sidekiq.dump_json(
            {
              jid: "jid_#{index}",
              task_name: "task_#{index}",
              args: {},
              enqueued_at: current_time.to_f,
            }
          )

          conn.lpush("task:foo:bar:history", task_trace)
        end
      end

      storage.store_history("a1b2c3", {"bar" => "baz"}, current_time)
      expect(storage.history.size).to eq(storage.history_limit)
      expect(storage.history.map { |task_trace| task_trace["jid"] }).to eq(["a1b2c3", "jid_2", "jid_1"])
    end
  end

  describe "#store_enqueue" do
    before { clear_redis }

    it "stores the task history and last enqueue at time", :aggregate_failures do
      current_time = Time.now
      expect(Time).to receive(:now).and_return(current_time)
      storage = described_class.new("foo:bar", history_limit: 10)
      storage.store_enqueue("a1b2c3", {"bar" => "baz"})

      expect(storage.last_enqueue_at).to eq(Time.at(current_time.to_f))
      expect(storage.history.size).to eq(1)
      expect(storage.history.first).to eq(
        {
          "jid" => "a1b2c3",
          "task_name" => "foo:bar",
          "args" => {"bar" => "baz"},
          "enqueued_at" => Time.at(current_time.to_f),
        }
      )
    end

    it "stores user in the history when provided", :aggregate_failures do
      current_time = Time.now
      expect(Time).to receive(:now).and_return(current_time)
      user = {"id" => 1, "email" => "admin@example.com"}
      storage = described_class.new("foo:bar", history_limit: 10)
      storage.store_enqueue("a1b2c3", {"bar" => "baz"}, user: user)

      expect(storage.history.size).to eq(1)
      expect(storage.history.first).to eq(
        {
          "jid" => "a1b2c3",
          "task_name" => "foo:bar",
          "args" => {"bar" => "baz"},
          "enqueued_at" => Time.at(current_time.to_f),
          "user" => {"id" => 1, "email" => "admin@example.com"},
        }
      )
    end
  end

  describe "#store_execution" do
    before { clear_redis }

    it "stores the task execution time in the history with the given time key", :aggregate_failures do
      current_time = Time.now.to_f
      expect(Time).to receive(:now).twice.and_return(current_time)
      storage = described_class.new("foo:bar", history_limit: 10)
      storage.store_enqueue("a1b2c3", {"bar" => "baz"})

      storage.store_execution("a1b2c3", "executed_at")

      expect(storage.history.size).to eq(1)
      expect(storage.history.first).to eq(
        {
          "jid" => "a1b2c3",
          "task_name" => "foo:bar",
          "args" => {"bar" => "baz"},
          "enqueued_at" => Time.at(current_time),
          "executed_at" => Time.at(current_time),
        }
      )
    end

    it "does nothing when the task is not found", :aggregate_failures do
      current_time = Time.now
      expect(Time).to receive(:now).and_return(current_time)
      storage = described_class.new("foo:bar", history_limit: 10)
      storage.store_enqueue("a1b2c3", {"bar" => "baz"})

      storage.store_execution("b1b2c3", "executed_at")

      expect(storage.history.size).to eq(1)
      expect(storage.history.first).to eq(
        {
          "jid" => "a1b2c3",
          "task_name" => "foo:bar",
          "args" => {"bar" => "baz"},
          "enqueued_at" => Time.at(current_time.to_f),
        }
      )
    end
  end

  describe "#store_execution_error" do
    before { clear_redis }

    it "stores the error message in the history with the given jid", :aggregate_failures do
      current_time = Time.now
      expect(Time).to receive(:now).and_return(current_time)
      storage = described_class.new("foo:bar", history_limit: 10)
      storage.store_enqueue("a1b2c3", {"bar" => "baz"})

      error = StandardError.new("An error occurred")
      storage.store_execution_error("a1b2c3", error)

      expect(storage.history.size).to eq(1)
      expect(storage.history.first).to eq(
        {
          "jid" => "a1b2c3",
          "task_name" => "foo:bar",
          "args" => {"bar" => "baz"},
          "enqueued_at" => Time.at(current_time.to_f),
          "error" => "StandardError: An error occurred",
        }
      )
    end

    it "truncates the error message when it exceeds the maximum length", :aggregate_failures do
      stub_const("Sidekiq::Tasks::Storage::Base::ERROR_MESSAGE_MAX_LENGTH", 40)

      current_time = Time.now
      expect(Time).to receive(:now).and_return(current_time)
      storage = described_class.new("foo:bar", history_limit: 10)
      storage.store_enqueue("a1b2c3", {"bar" => "baz"})

      error = StandardError.new("An error occurred: this is an error message")
      storage.store_execution_error("a1b2c3", error)

      expect(storage.history.size).to eq(1)
      expect(storage.history.first).to eq(
        {
          "jid" => "a1b2c3",
          "task_name" => "foo:bar",
          "args" => {"bar" => "baz"},
          "enqueued_at" => Time.at(current_time.to_f),
          "error" => "StandardError: An error occurred: thi...",
        }
      )
    end
  end

  describe "#store_dry_run and #store_execution_report" do
    before { clear_redis }

    it "stores the dry run flag and the report in the history entry" do
      storage = described_class.new("foo:bar", history_limit: 10)
      storage.store_enqueue("a1b2c3", {})
      storage.store_dry_run("a1b2c3")
      storage.store_execution_report(
        "a1b2c3",
        {"values" => {"success" => 2}, "lists" => {"failed" => {"items" => [{"id" => 1}], "count" => 1}}}
      )

      expect(storage.history.first).to include(
        "dry_run" => true,
        "report" => {"values" => {"success" => 2}, "lists" => {"failed" => {"items" => [{"id" => 1}], "count" => 1}}}
      )
    end
  end

  describe "#report_max_bytes" do
    it "returns the configured report_max_bytes within the task reports budget", :aggregate_failures do
      allow(Sidekiq::Tasks.config).to receive(:report_max_bytes).and_return(1024 * 1024)

      expect(described_class.new("foo:bar", history_limit: 10).report_max_bytes).to eq(1024 * 1024)
      expect(described_class.new("foo:bar", history_limit: 100).report_max_bytes).to eq(104_857)
      expect(described_class.new("foo:bar", history_limit: 1_000).report_max_bytes * 1_000).to(
        be <= described_class::TASK_REPORTS_BUDGET
      )
    end
  end
end
