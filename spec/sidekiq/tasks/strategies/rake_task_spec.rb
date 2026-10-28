require "spec_helper"

RSpec.describe Sidekiq::Tasks::Strategies::RakeTask do
  describe "#load_tasks" do
    it "loads the rake tasks from the rake application", :aggregate_failures do
      strategy = described_class.new
      rake_tasks = [build_rake_task]
      expect(Rake::TaskManager).to receive(:record_task_metadata=).with(true)
      expect(Rake).to receive_message_chain(:application, :load_rakefile)
      expect(Rake::Task).to receive(:tasks).and_return(rake_tasks)
      expect(strategy.load_tasks).to eq(rake_tasks)
    end
  end

  describe "#build_task_metadata" do
    it "builds the metadata for a task", :aggregate_failures do
      rake_task = build_rake_task(
        name: "foo:bar",
        full_comment: "Bar",
        locations: ["foo.rb:2"],
        arg_names: ["bar"]
      )

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          task :bar do
          end
        end
      RUBY

      metadata = described_class.new.build_task_metadata(rake_task)

      expect(metadata).to be_a(Sidekiq::Tasks::TaskMetadata)
      expect(metadata.name).to eq("foo:bar")
      expect(metadata.desc).to eq("Bar")
      expect(metadata.file).to eq("foo.rb")
      expect(metadata.args).to eq(["bar"])
      expect(metadata.sidekiq_options).to eq({})
      expect(metadata.dry_run?).to eq(false)
    end

    it "enables dry run from a magic comment" do
      rake_task = build_rake_task(name: "foo:bar", full_comment: nil, locations: ["foo.rb:3"], arg_names: [])

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          # sidekiq-tasks:dry_run
          task :bar do
          end
        end
      RUBY

      expect(described_class.new.build_task_metadata(rake_task).dry_run?).to eq(true)
    end

    it "extracts sidekiq_options from a magic comment", :aggregate_failures do
      rake_task = build_rake_task(
        name: "foo:bar",
        full_comment: nil,
        locations: ["foo.rb:3"],
        arg_names: []
      )

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          # sidekiq-tasks:sidekiq_options: queue: critical, retry: 5
          task :bar do
          end
        end
      RUBY

      metadata = described_class.new.build_task_metadata(rake_task)

      expect(metadata.sidekiq_options).to eq(queue: "critical", retry: 5)
    end

    it "prefers the task sidekiq_options over the namespace ones" do
      rake_task = build_rake_task(name: "foo:bar", full_comment: nil, locations: ["foo.rb:4"], arg_names: [])

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        # sidekiq-tasks:sidekiq_options: queue: low, retry: 3
        namespace :foo do
          # sidekiq-tasks:sidekiq_options: queue: critical
          task :bar do
          end
        end
      RUBY

      expect(described_class.new.build_task_metadata(rake_task).sidekiq_options).to eq(queue: "critical")
    end

    it "returns a broken metadata when sidekiq_options YAML is invalid", :aggregate_failures do
      rake_task = build_rake_task(
        name: "foo:bar",
        full_comment: nil,
        locations: ["foo.rb:3"],
        arg_names: []
      )

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          # sidekiq-tasks:sidekiq_options: queue: 'unterminated
          task :bar do
          end
        end
      RUBY

      metadata = described_class.new.build_task_metadata(rake_task)

      expect(metadata.error?).to be(true)
      expect(metadata.name).to eq("foo:bar")
      expect(metadata.file).to eq("foo.rb")
      expect(metadata.error).to match(/not valid YAML/)
    end
  end

  describe "#execute_task" do
    it "executes the task with the given params" do
      rake_task = build_rake_task(name: "foo:bar")

      expect(Rake::Task).to receive(:[]).with("foo:bar").and_return(rake_task)
      expect(rake_task).to receive(:execute).with({bar: "baz"})

      described_class.new.execute_task("foo:bar", {bar: "baz"})
    end
  end
end
