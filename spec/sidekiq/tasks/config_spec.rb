require "spec_helper"

RSpec.describe Sidekiq::Tasks::Config do
  describe "#initialize" do
    it "sets the default sidekiq options" do
      expect(described_class.new.sidekiq_options).to eq({queue: "default", retry: false})
    end

    it "sets the default strategies" do
      expect(described_class.new.strategies).to match_array(
        [
          an_instance_of(Sidekiq::Tasks::Strategies::RakeTask).and(
            have_attributes(
              rules: [
                an_instance_of(Sidekiq::Tasks::Strategies::Rules::TaskFromLib),
                an_instance_of(Sidekiq::Tasks::Strategies::Rules::EnableWithComment),
              ]
            )
          ),
        ]
      )
    end

    it "sets the default storage" do
      expect(described_class.new.storage).to eq(Sidekiq::Tasks::Storage::Redis)
    end

    it "sets the default authorization proc" do
      expect(described_class.new.authorization).to be_a(Proc)
      expect(described_class.new.authorization.call({})).to eq(true)
    end
  end

  describe "#sidekiq_options=" do
    it "sets the sidekiq options" do
      config = described_class.new

      sidekiq_options = {
        queue: "foo",
        retry: true,
        dead: true,
        backtrace: true,
        pool: "default",
        tags: ["foo"],
      }

      config.sidekiq_options = sidekiq_options
      expect(config.sidekiq_options).to eq(sidekiq_options)
    end

    it "raises an error when the sidekiq options are not a Hash" do
      expect { described_class.new.sidekiq_options = "foo" }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'sidekiq_options' must be an instance of Hash but received String"
        )
      )
    end

    it "raises an error when the queue key is invalid", :aggregate_failures do
      expect { described_class.new.sidekiq_options = {queue: nil, retry: true} }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'queue' must be an instance of String but received NilClass"
        )
      )

      expect { described_class.new.sidekiq_options = {queue: :foo, retry: true} }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'queue' must be an instance of String but received Symbol"
        )
      )
    end

    it "does not raise an error when the retry key is valid", :aggregate_failures do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: nil} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: true} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: 5} }.not_to raise_error
    end

    it "raises an error when the retry key is invalid" do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: "foo"} }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'retry' must be an instance of NilClass or TrueClass or FalseClass or Integer but received String"
        )
      )
    end

    it "does not raise an error when the retry_for key is valid", :aggregate_failures do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry_for: nil} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry_for: 3600} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry_for: 172_800.0} }.not_to raise_error
    end

    it "raises an error when the retry_for key is invalid" do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry_for: "foo"} }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'retry_for' must be an instance of NilClass or Integer or Float but received String"
        )
      )
    end

    it "raises an error when the dead key is invalid" do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, dead: "foo"} }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'dead' must be an instance of NilClass or TrueClass or FalseClass but received String"
        )
      )
    end

    it "does not raise an error when the dead key is nil", :aggregate_failures do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, dead: nil} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, dead: false} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, dead: true} }.not_to raise_error
    end

    it "raises an error when the backtrace key is invalid" do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, backtrace: "foo"} }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'backtrace' must be an instance of NilClass or TrueClass or FalseClass or Integer but received String"
        )
      )
    end

    it "does not raise an error when the backtrace key is nil", :aggregate_failures do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, backtrace: nil} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, backtrace: false} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, backtrace: true} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, backtrace: 0} }.not_to raise_error
    end

    it "raises an error when the pool key is invalid" do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, pool: 1} }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'pool' must be an instance of NilClass or String but received Integer"
        )
      )
    end

    it "does not raise an error when the pool key is nil", :aggregate_failures do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, pool: nil} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, pool: "default"} }.not_to raise_error
    end

    it "raises an error when the tags key is invalid" do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, tags: 1} }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'tags' must be an instance of NilClass or Array but received Integer"
        )
      )
    end

    it "does not raise an error when the tags key is nil", :aggregate_failures do
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, tags: nil} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, tags: []} }.not_to raise_error
      expect { described_class.new.sidekiq_options = {queue: "foo", retry: false, tags: ["foo"]} }.not_to raise_error
    end
  end

  describe "#strategies=" do
    it "sets the strategies" do
      config = described_class.new
      strategies = [Sidekiq::Tasks::Strategies::RakeTask.new]
      config.strategies = strategies
      expect(config.strategies).to eq(strategies)
    end

    it "raises an error when the strategies are not an array" do
      expect { described_class.new.strategies = "foo" }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'strategies' must be an instance of Array but received String"
        )
      )
    end

    it "raises an error when the strategies are not instances of Sidekiq::Tasks::Strategies::Base" do
      expect { described_class.new.strategies = ["foo"] }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'foo' must be an instance of Sidekiq::Tasks::Strategies::Base but received String"
        )
      )
    end
  end

  describe "#storage=" do
    it "sets the storage class" do
      config = described_class.new
      custom_storage = Class.new(Sidekiq::Tasks::Storage::Base)
      config.storage = custom_storage
      expect(config.storage).to eq(custom_storage)
    end

    it "raises an error when the storage is not a class inheriting from Storage::Base" do
      expect { described_class.new.storage = "foo" }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'storage' must be a class inheriting from Sidekiq::Tasks::Storage::Base but received \"foo\""
        )
      )
    end

    it "raises an error when the storage is a class not inheriting from Storage::Base" do
      expect { described_class.new.storage = String }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'storage' must be a class inheriting from Sidekiq::Tasks::Storage::Base but received String"
        )
      )
    end
  end

  describe "report limits" do
    it "lowers a too large report_max_bytes to the limit, with a warning", :aggregate_failures do
      config = described_class.new
      expect(Sidekiq.logger).to receive(:warn).with(/'report_max_bytes' \(10485760\) exceeds the maximum, using 1048576/)

      config.report_max_bytes = 10 * 1024 * 1024

      expect(config.report_max_bytes).to eq(1024 * 1024)
    end

    it "does not warn for values within the limits" do
      expect(Sidekiq.logger).not_to receive(:warn)

      config = described_class.new
      config.report_max_bytes = 1024 * 1024
    end
  end

  describe "#report_max_bytes=" do
    it "defaults to 64 KB" do
      expect(described_class.new.report_max_bytes).to eq(65_536)
    end

    it "sets the report max bytes" do
      config = described_class.new
      config.report_max_bytes = 1024
      expect(config.report_max_bytes).to eq(1024)
    end

    it "raises an error when the report max bytes is invalid", :aggregate_failures do
      expect { described_class.new.report_max_bytes = "10" }.to(
        raise_error(Sidekiq::Tasks::ArgumentError, "'report_max_bytes' must be an instance of Integer but received String")
      )
      expect { described_class.new.report_max_bytes = 0 }.to(
        raise_error(Sidekiq::Tasks::ArgumentError, "'report_max_bytes' must be greater than 0")
      )
    end
  end

  describe "#history_limit=" do
    it "defaults to 10" do
      expect(described_class.new.history_limit).to eq(10)
    end

    it "sets the history limit" do
      config = described_class.new
      config.history_limit = 25
      expect(config.history_limit).to eq(25)
    end

    it "raises an error when the history limit is not an Integer" do
      expect { described_class.new.history_limit = "10" }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'history_limit' must be an instance of Integer but received String"
        )
      )
    end

    it "raises an error when the history limit is less than or equal to 0", :aggregate_failures do
      expect { described_class.new.history_limit = 0 }.to(
        raise_error(Sidekiq::Tasks::ArgumentError, "'history_limit' must be greater than 0")
      )

      expect { described_class.new.history_limit = -1 }.to(
        raise_error(Sidekiq::Tasks::ArgumentError, "'history_limit' must be greater than 0")
      )
    end
  end

  describe "#current_user=" do
    it "defaults to nil" do
      expect(described_class.new.current_user).to be_nil
    end

    it "sets the current_user proc" do
      config = described_class.new
      current_user_proc = ->(_env) { {id: 1, email: "admin@example.com"} }
      config.current_user = current_user_proc
      expect(config.current_user).to eq(current_user_proc)
    end

    it "raises an error when not a Proc" do
      expect { described_class.new.current_user = "foo" }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'current_user' must be an instance of Proc but received String"
        )
      )
    end
  end

  describe "#authorization=" do
    it "sets the authorization proc" do
      config = described_class.new
      authorization_proc = ->(_env) { true }
      config.authorization = authorization_proc
      expect(config.authorization).to eq(authorization_proc)
    end

    it "raises an error when the authorization is not a Proc" do
      expect { described_class.new.authorization = "foo" }.to(
        raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'authorization' must be an instance of Proc but received String"
        )
      )
    end
  end
end
