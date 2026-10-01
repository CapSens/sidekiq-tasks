require "spec_helper"

RSpec.describe Sidekiq::Tasks::Strategies::Base do
  describe "#name" do
    it "returns the name of the strategy class" do
      test_strategy_klass = stub_const("TestStrategy", Class.new(described_class))
      expect(test_strategy_klass.new.name).to eq("TestStrategy")
    end
  end

  describe "#load_tasks" do
    it "raises an error when the strategy is not implemented" do
      expect { described_class.new.load_tasks }.to raise_error(
        Sidekiq::Tasks::NotImplementedError,
        "Strategy must implement #load_tasks"
      )
    end
  end

  describe "#execute_task" do
    it "raises an error when the strategy is not implemented" do
      expect { described_class.new.execute_task("foo", {}) }.to raise_error(
        Sidekiq::Tasks::NotImplementedError,
        "Strategy must implement #execute_task"
      )
    end
  end

  describe "#enqueue_task" do
    it "enqueues a task with the given name and json params, and returns the JID", :aggregate_failures do
      name, params = ["foo:bar", {"bar" => "baz"}]
      expect(Sidekiq::Tasks::Job).to receive(:perform_async).with(name, params.to_json, false).and_return("a1b2c3")
      expect(described_class.new.enqueue_task(name, params)).to eq("a1b2c3")
    end

    it "applies per-task sidekiq_options through Sidekiq::Job.set when present", :aggregate_failures do
      name, params, opts = ["foo:bar", {"bar" => "baz"}, {queue: "critical", retry: 5}]
      configurator = double("configurator")
      expect(Sidekiq::Tasks::Job).to receive(:set).with(opts).and_return(configurator)
      expect(configurator).to receive(:perform_async).with(name, params.to_json, false).and_return("a1b2c3")

      expect(described_class.new.enqueue_task(name, params, sidekiq_options: opts)).to eq("a1b2c3")
    end

    it "uses Job.perform_async directly when sidekiq_options is empty" do
      expect(Sidekiq::Tasks::Job).not_to receive(:set)
      expect(Sidekiq::Tasks::Job).to receive(:perform_async).with("foo", "{}", false)

      described_class.new.enqueue_task("foo", {}, sidekiq_options: {})
    end

    it "enqueues a task in dry run mode" do
      name, params = ["foo:bar", {"bar" => "baz"}]
      expect(Sidekiq::Tasks::Job).to receive(:perform_async).with(name, params.to_json, true).and_return("a1b2c3")
      expect(described_class.new.enqueue_task(name, params, dry_run: true)).to eq("a1b2c3")
    end
  end

  describe "#build_task_metadata" do
    it "raises an error when the strategy is not implemented" do
      expect { described_class.new.build_task_metadata(build_rake_task) }.to raise_error(
        Sidekiq::Tasks::NotImplementedError,
        "Strategy must implement #build_task_metadata"
      )
    end
  end

  describe "#tasks" do
    let(:tasks) do
      [
        {name: "foo", file: "foo.rb"},
        {name: "bar", file: "bar.rb"},
        {name: "baz", file: "baz.rb"},
      ]
    end

    it "returns the tasks that respect the rules" do
      foo_bar_rule = build_strategy_rule do
        def respected?(task)
          task[:name].match?(/foo|bar/)
        end
      end

      strategy = build_strategy(rules: [foo_bar_rule])

      expect(strategy).to receive(:load_tasks).and_return(tasks)
      expect(strategy).to receive(:build_task_metadata).exactly(2).times.and_wrap_original do |_, args|
        Sidekiq::Tasks::TaskMetadata.new(**args)
      end
      expect(strategy.tasks.map { |task| {name: task.name, file: task.file} }).to eq(tasks.first(2))
    end

    it "returns an empty array when no tasks respect the rules", :aggregate_failures do
      toto_tata_rule = build_strategy_rule do
        def respected?(task)
          task[:name].match?(/toto|tata/)
        end
      end

      strategy = build_strategy(rules: [toto_tata_rule])
      expect(strategy).to receive(:load_tasks).and_return(tasks)
      expect(strategy).not_to receive(:build_task_metadata)
      expect(strategy.tasks).to eq([])
    end

    it "returns all loaded tasks when no rules are provided", :aggregate_failures do
      strategy = build_strategy

      expect(strategy).to receive(:load_tasks).and_return(tasks)
      expect(strategy).to receive(:build_task_metadata).exactly(3).times.and_wrap_original do |_, args|
        Sidekiq::Tasks::TaskMetadata.new(**args)
      end
      expect(strategy.tasks.map { |task| {name: task.name, file: task.file} }).to eq(tasks)
    end
  end
end
