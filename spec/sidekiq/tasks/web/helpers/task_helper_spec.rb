require "spec_helper"

RSpec.describe Sidekiq::Tasks::Web::Helpers::TaskHelper do
  describe "#parameterize_task_name" do
    it "replaces colons with dashes" do
      expect(described_class.parameterize_task_name("foo")).to eq("foo")
      expect(described_class.parameterize_task_name("foo:bar")).to eq("foo-bar")
      expect(described_class.parameterize_task_name("foo:bar:baz")).to eq("foo-bar-baz")
    end
  end

  describe "#unparameterize_task_name" do
    it "replaces dashes with colons" do
      expect(described_class.unparameterize_task_name("foo")).to eq("foo")
      expect(described_class.unparameterize_task_name("foo-bar")).to eq("foo:bar")
      expect(described_class.unparameterize_task_name("foo-bar-baz")).to eq("foo:bar:baz")
    end
  end

  describe "#find_task!" do
    it "finds the task by name" do
      task = build_task(name: "foo:bar")
      allow(Sidekiq::Tasks).to receive(:tasks).and_return(build_task_set(task))
      expect(described_class.find_task!("foo:bar")).to eq(task)
    end

    it "raises an error when the task is not found" do
      allow(Sidekiq::Tasks).to receive(:tasks).and_return(build_task_set)
      expect { described_class.find_task!("foo:bar") }.to raise_error(Sidekiq::Tasks::NotFoundError)
    end
  end

  describe "#task_url" do
    it "returns the URL for the given task and root path replacing the colon with a dash" do
      expect(described_class.task_url("/sidekiq/", build_task(name: "foo:bar"))).to eq("/sidekiq/tasks/foo-bar")
    end
  end

  describe "#task_status" do
    it "returns :failure when error is present" do
      jid_history = {"error" => "Some error"}
      expect(described_class.task_status(jid_history)).to eq(:failure)
    end

    it "returns :success when there is no error and finished_at is present" do
      jid_history = {"finished_at" => Time.now}
      expect(described_class.task_status(jid_history)).to eq(:success)
    end

    it "returns :running when there is no error, no finished_at, and executed_at is present" do
      jid_history = {"executed_at" => Time.now}
      expect(described_class.task_status(jid_history)).to eq(:running)
    end

    it "returns :pending when there is no error, no finished_at, and no executed_at" do
      jid_history = {}
      expect(described_class.task_status(jid_history)).to eq(:pending)
    end
  end

  describe "#format_task_duration" do
    it "returns '-' when start_time or end_time is nil", :aggregate_failures do
      expect(described_class.format_task_duration(nil, nil)).to eq("-")
      expect(described_class.format_task_duration(Time.now, nil)).to eq("-")
      expect(described_class.format_task_duration(nil, Time.now)).to eq("-")
    end

    it "returns the duration in seconds when greater than or equal to 1 second", :aggregate_failures do
      start_time = Time.now
      end_time = start_time + 2
      expect(described_class.format_task_duration(start_time, end_time)).to eq("2s")
    end

    it "returns the duration in milliseconds when less than 1 second", :aggregate_failures do
      start_time = Time.now
      end_time = start_time + 0.42
      expect(described_class.format_task_duration(start_time, end_time)).to eq("420ms")
    end
  end

  describe "#format_task_sidekiq_options" do
    it "formats the task overrides as a oneline string", :aggregate_failures do
      task = build_task(sidekiq_options: {queue: "critical", retry: 5})

      expect(described_class.format_task_sidekiq_options(task)).to eq("queue: critical, retry: 5")
    end

    it "returns an empty string when the task has no override" do
      expect(described_class.format_task_sidekiq_options(build_task(sidekiq_options: {}))).to eq("")
    end

    it "wraps array values in brackets" do
      task = build_task(sidekiq_options: {tags: ["daily", "critical"]})

      expect(described_class.format_task_sidekiq_options(task)).to eq("tags: [daily, critical]")
    end
  end

  describe "#format_sidekiq_option_value" do
    it "wraps arrays in brackets" do
      expect(described_class.format_sidekiq_option_value(["a", "b"])).to eq("[a, b]")
    end

    it "returns '-' for nil" do
      expect(described_class.format_sidekiq_option_value(nil)).to eq("-")
    end

    it "stringifies other values", :aggregate_failures do
      expect(described_class.format_sidekiq_option_value("critical")).to eq("critical")
      expect(described_class.format_sidekiq_option_value(5)).to eq("5")
      expect(described_class.format_sidekiq_option_value(false)).to eq("false")
    end
  end
end
