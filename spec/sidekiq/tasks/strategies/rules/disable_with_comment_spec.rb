require "spec_helper"

RSpec.describe Sidekiq::Tasks::Strategies::Rules::DisableWithComment do
  describe "#respected?" do
    it "is respected when the task has no magic comment", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:2"], full_comment: nil)

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          task :bar do
            puts "bar"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to eq(true)
    end

    it "is not respected when the task has a magic comment before the task", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:3"], full_comment: nil)

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          # sidekiq-tasks:disable
          task :bar do
            puts "bar"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to eq(false)
    end

    it "is not respected when the task has a magic comment before the desc", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:4"], full_comment: "Bar")

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          # sidekiq-tasks:disable
          desc "Bar"
          task :bar do
            puts "bar"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to eq(false)
    end

    it "is not respected when the task has a magic comment after the desc", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:4"], full_comment: "Bar")

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          desc "Bar"
          # sidekiq-tasks:disable
          task :bar do
            puts "bar"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to eq(false)
    end

    it "is respected when the task has a magic comment after the task", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:2"], full_comment: nil)

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          task :bar do
            puts "bar"
          end
          # sidekiq-tasks:disable
        end
      RUBY

      expect(described_class.new.respected?(task)).to eq(true)
    end

    it "is not respected when the task has a magic comment before the namespace", :aggregate_failures do
      bar_task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:3"], full_comment: nil)
      baz_task = instance_double(Rake::Task, name: "foo:baz", locations: ["foo.rb:7"], full_comment: nil)

      expect(File).to receive(:read).exactly(2).times.with("foo.rb").and_return <<~RUBY
        # sidekiq-tasks:disable
        namespace :foo do
          task :bar do
            puts "bar"
          end

          task :baz do
            puts "baz"
          end
        end
      RUBY

      expect(described_class.new.respected?(bar_task)).to eq(false)
      expect(described_class.new.respected?(baz_task)).to eq(false)
    end

    it "works with multiple tasks", :aggregate_failures do
      enabled_task_before_disabled_task = instance_double(
        Rake::Task,
        name: "foo:bar",
        locations: ["foo.rb:3"],
        full_comment: "Send an order confirmation email"
      )

      disabled_task = instance_double(
        Rake::Task,
        name: "foo:baz",
        locations: ["foo.rb:8"],
        full_comment: nil
      )

      enabled_task_after_disabled_task = instance_double(
        Rake::Task,
        name: "foo:buz",
        locations: ["foo.rb:12"],
        full_comment: nil
      )

      expect(File).to receive(:read).with("foo.rb").exactly(3).times.and_return <<~RUBY
        namespace :foo do
          desc "Send an order confirmation email"
          task :bar do
            puts "bar"
          end

          # sidekiq-tasks:disable
          task :baz do
            puts "baz"
          end

          task :buz do
            puts "buz"
          end
        end
      RUBY

      expect(described_class.new.respected?(enabled_task_before_disabled_task)).to eq(true)
      expect(described_class.new.respected?(disabled_task)).to eq(false)
      expect(described_class.new.respected?(enabled_task_after_disabled_task)).to eq(true)
    end

    it "raises an error when the file is not found" do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:2"], full_comment: nil)

      expect { described_class.new.respected?(task) }.to raise_error(
        Sidekiq::Tasks::ArgumentError,
        "File 'foo.rb' not found"
      )
    end

    it "is respected when the task has a magic comment before multi line desc" do
      disabled_task_with_heredoc_desc = instance_double(
        Rake::Task,
        name: "test:disabled_task_with_heredoc_desc",
        locations: ["test.rb:7"],
        full_comment: "foo\n    bar"
      )

      enabled_task = instance_double(
        Rake::Task,
        name: "test:enabled_task",
        locations: ["test.rb:12"],
        full_comment: "Not enabled task"
      )

      disabled_task_with_multiline_desc = instance_double(
        Rake::Task,
        name: "test:disabled_task_with_multiline_desc",
        locations: ["test.rb:21"],
        full_comment: "foo\n    bar"
      )

      expect(File).to receive(:read).exactly(3).times.with("test.rb").and_return <<~RUBY
        namespace :test do
          # sidekiq-tasks:disable
          desc <<-DESC
            foo
            bar
          DESC
          task :disabled_task_with_heredoc_desc do
            puts "bar"
          end

          desc "Enabled task"
          task :enabled_task do
            puts "baz"
          end

          # sidekiq-tasks:disable
          desc "
            foo
            bar
          "
          task :disabled_task_with_multiline_desc do
            puts "bar"
          end
        end
      RUBY

      aggregate_failures do
        expect(described_class.new.respected?(disabled_task_with_heredoc_desc)).to be(false)
        expect(described_class.new.respected?(enabled_task)).to be(true)
        expect(described_class.new.respected?(disabled_task_with_multiline_desc)).to be(false)
      end
    end
  end
end
