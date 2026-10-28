require "spec_helper"

RSpec.describe Sidekiq::Tasks do
  it "has a version number" do
    expect(Sidekiq::Tasks::VERSION).not_to be_nil
  end

  describe ".configure" do
    it "yields a Sidekiq::Tasks::Config instance" do
      expect { |block| described_class.configure(&block) }.to yield_with_args(Sidekiq::Tasks::Config)
    end
  end

  describe ".config" do
    before do
      described_class.instance_variable_set(:@_config, nil)
    end

    it "returns a memoized instance of Sidekiq::Tasks::Config", :aggregate_failures do
      config = described_class.config
      expect(config).to be_a(Sidekiq::Tasks::Config)
      expect(described_class.config.object_id).to eq(config.object_id)
    end
  end

  describe ".strategies" do
    before do
      described_class.instance_variable_set(:@_strategies, nil)
    end

    it "returns memoized set of strategies", :aggregate_failures do
      strategies = [build_strategy, build_strategy]

      expect(described_class.config).to receive(:strategies).and_return(strategies)

      set = described_class.strategies

      expect(set.objects).to eq(strategies)
      expect(set).to be_a(Sidekiq::Tasks::Set)
      expect(set.object_id).to eq(described_class.strategies.object_id)
    end
  end

  describe ".tasks" do
    before do
      described_class.instance_variable_set(:@_tasks, nil)
    end

    it "finds tasks and returns a memoized instance of Sidekiq::Tasks::Set", :aggregate_failures do
      strategy = build_strategy
      tasks = [build_task(name: "foo:bar")]

      expect(described_class).to receive(:strategies).and_return([strategy])
      expect(strategy).to receive(:tasks).and_return(tasks)

      set = described_class.tasks

      expect(set.objects).to eq(tasks)
      expect(set).to be_a(Sidekiq::Tasks::Set)
      expect(set.object_id).to eq(described_class.tasks.object_id)
    end
  end

  describe ".current_run" do
    it "returns the run of the task being executed" do
      run = Sidekiq::Tasks::Run.new(dry_run: true)
      Sidekiq::Tasks::Run.with(run) { expect(described_class.current_run).to eq(run) }
    end
  end

  describe ".dry_run? and .report" do
    it "delegate to the current run", :aggregate_failures do
      run = Sidekiq::Tasks::Run.new(dry_run: true)

      Sidekiq::Tasks::Run.with(run) do
        expect(described_class.dry_run?).to eq(true)
        expect(described_class.report).to eq(run.report)
      end
    end
  end
end
