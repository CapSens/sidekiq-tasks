require "spec_helper"

RSpec.describe Sidekiq::Tasks::Strategies::Rules::EnableWithComment do
  describe "#respected?" do
    it "is not respected when the task has no magic comment", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:2"], full_comment: nil)

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          task :bar do
            puts "bar"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(false)
    end

    it "is respected when the task has a magic comment before the task", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:3"], full_comment: nil)

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          # sidekiq-tasks:enable
          task :bar do
            puts "bar"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(true)
    end

    it "is respected when the task has a magic comment before the desc", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:4"], full_comment: "Bar")

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          # sidekiq-tasks:enable
          desc "Bar"
          task :bar do
            puts "bar"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(true)
    end

    it "is respected when the task has a magic comment after the desc", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:4"], full_comment: "Bar")

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          desc "Bar"
          # sidekiq-tasks:enable
          task :bar do
            puts "bar"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(true)
    end

    it "is not respected when the task has a magic comment after the task", :aggregate_failures do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:2"], full_comment: nil)

      expect(File).to receive(:read).with("foo.rb").and_return <<~RUBY
        namespace :foo do
          task :bar do
            puts "bar"
          end
          # sidekiq-tasks:enable
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(false)
    end

    it "is respected when the task has a magic comment before the namespace", :aggregate_failures do
      bar_task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:3"], full_comment: nil)
      baz_task = instance_double(Rake::Task, name: "foo:baz", locations: ["foo.rb:7"], full_comment: nil)

      expect(File).to receive(:read).exactly(2).times.with("foo.rb").and_return <<~RUBY
        # sidekiq-tasks:enable
        namespace :foo do
          task :bar do
            puts "bar"
          end

          task :baz do
            puts "baz"
          end
        end
      RUBY

      expect(described_class.new.respected?(bar_task)).to be(true)
      expect(described_class.new.respected?(baz_task)).to be(true)
    end

    it "works with multiple tasks", :aggregate_failures do
      not_enabled_task_before_enabled_task = instance_double(
        Rake::Task,
        name: "foo:bar",
        locations: ["foo.rb:3"],
        full_comment: "Send an order confirmation email"
      )

      enabled_task = instance_double(
        Rake::Task,
        name: "foo:baz",
        locations: ["foo.rb:8"],
        full_comment: nil
      )

      not_enabled_task_after_enabled_task = instance_double(
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

          # sidekiq-tasks:enable
          task :baz do
            puts "baz"
          end

          task :buz do
            puts "buz"
          end
        end
      RUBY

      expect(described_class.new.respected?(not_enabled_task_before_enabled_task)).to be(false)
      expect(described_class.new.respected?(enabled_task)).to be(true)
      expect(described_class.new.respected?(not_enabled_task_after_enabled_task)).to be(false)
    end

    it "raises an error when the file is not found" do
      task = instance_double(Rake::Task, name: "foo:bar", locations: ["foo.rb:2"], full_comment: nil)

      expect { described_class.new.respected?(task) }.to raise_error(
        Sidekiq::Tasks::ArgumentError,
        "File 'foo.rb' not found"
      )
    end

    it "is respected when the task has a magic comment before multi line desc" do
      enabled_task_with_heredoc_desc = instance_double(
        Rake::Task,
        name: "test:enabled_task_with_heredoc_desc",
        locations: ["test.rb:7"],
        full_comment: "foo\n    bar"
      )

      not_enabled_task = instance_double(
        Rake::Task,
        name: "test:not_enabled_task",
        locations: ["test.rb:12"],
        full_comment: "Not enabled task"
      )

      enabled_task_with_multiline_desc = instance_double(
        Rake::Task,
        name: "test:enabled_task_with_multiline_desc",
        locations: ["test.rb:21"],
        full_comment: "foo\n    bar"
      )

      expect(File).to receive(:read).exactly(3).times.with("test.rb").and_return <<~RUBY
        namespace :test do
          # sidekiq-tasks:enable
          desc <<-DESC
            foo
            bar
          DESC
          task :enabled_task_with_heredoc_desc do
            puts "bar"
          end

          desc "Not enabled task"
          task :not_enabled_task do
            puts "baz"
          end

          # sidekiq-tasks:enable
          desc "
            foo
            bar
          "
          task :enabled_task_with_multiline_desc do
            puts "bar"
          end
        end
      RUBY

      aggregate_failures do
        expect(described_class.new.respected?(enabled_task_with_heredoc_desc)).to be(true)
        expect(described_class.new.respected?(not_enabled_task)).to be(false)
        expect(described_class.new.respected?(enabled_task_with_multiline_desc)).to be(true)
      end
    end

    it "is respected when the heredoc content contains a line starting with 'desc'" do
      task = instance_double(
        Rake::Task,
        name: "test:cleanup",
        locations: ["test.rb:7"],
        full_comment: "This is a multiline\ndescription for testing"
      )

      expect(File).to receive(:read).with("test.rb").and_return <<~RUBY
        namespace :test do
          # sidekiq-tasks:enable
          desc <<~DESC
            This is a multiline
            description for testing
          DESC
          task :cleanup do
            puts "cleanup"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(true)
    end

    it "is respected when the multiline string content contains a line starting with 'desc'" do
      task = instance_double(
        Rake::Task,
        name: "test:cleanup",
        locations: ["test.rb:5"],
        full_comment: "Cleanup old records.\ndescribe which records to remove"
      )

      expect(File).to receive(:read).with("test.rb").and_return <<~RUBY
        namespace :test do
          # sidekiq-tasks:enable
          desc "Cleanup old records.
          describe which records to remove"
          task :cleanup do
            puts "cleanup"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(true)
    end

    it "is not respected when there is no magic comment even with desc-like content" do
      task = instance_double(
        Rake::Task,
        name: "test:cleanup",
        locations: ["test.rb:6"],
        full_comment: "Cleanup old records.\ndescription of removal process"
      )

      expect(File).to receive(:read).with("test.rb").and_return <<~RUBY
        namespace :test do
          desc <<~DESC
            Cleanup old records.
            description of removal process
          DESC
          task :cleanup do
            puts "cleanup"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(false)
    end

    it "is respected when the desc uses backslash continuation" do
      task = instance_double(
        Rake::Task,
        name: "foo:my_task",
        locations: ["test.rb:5"],
        full_comment: "Set investors_channel_created to true for selected projects. Use to stop the worker from retrying."
      )

      expect(File).to receive(:read).with("test.rb").and_return <<~RUBY
        namespace :foo do
          # sidekiq-tasks:enable
          desc "Set investors_channel_created to true for selected projects. " \\
               "Use to stop the worker from retrying."
          task :my_task do
            puts "hello"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(true)
    end

    it "is not respected when using backslash continuation without magic comment" do
      task = instance_double(
        Rake::Task,
        name: "foo:my_task",
        locations: ["test.rb:4"],
        full_comment: "Set investors_channel_created to true. Use to stop the worker from retrying."
      )

      expect(File).to receive(:read).with("test.rb").and_return <<~RUBY
        namespace :foo do
          desc "Set investors_channel_created to true. " \\
               "Use to stop the worker from retrying."
          task :my_task do
            puts "hello"
          end
        end
      RUBY

      expect(described_class.new.respected?(task)).to be(false)
    end
  end
end
