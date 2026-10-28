require "spec_helper"

RSpec.describe Sidekiq::Tasks::Storage::Base do
  let(:storage) { described_class.new("foo:bar") }

  describe "#initialize" do
    it "sets the task name" do
      expect(storage.task_name).to eq("foo:bar")
    end

    it "sets the history limit" do
      storage = described_class.new("foo:bar", history_limit: 25)
      expect(storage.history_limit).to eq(25)
    end

    it "defaults history limit to nil" do
      expect(storage.history_limit).to be_nil
    end
  end

  describe "#last_enqueue_at" do
    it "raises NotImplementedError" do
      expect { storage.last_enqueue_at }.to raise_error(
        Sidekiq::Tasks::NotImplementedError,
        "Storage must implement #last_enqueue_at"
      )
    end
  end

  describe "#history" do
    it "raises NotImplementedError" do
      expect { storage.history }.to raise_error(
        Sidekiq::Tasks::NotImplementedError,
        "Storage must implement #history"
      )
    end
  end

  describe "#store_enqueue" do
    it "raises NotImplementedError" do
      expect { storage.store_enqueue("jid", {}) }.to raise_error(
        Sidekiq::Tasks::NotImplementedError,
        "Storage must implement #store_enqueue"
      )
    end
  end

  describe "#store_execution" do
    it "raises NotImplementedError" do
      expect { storage.store_execution("jid", "executed_at") }.to raise_error(
        Sidekiq::Tasks::NotImplementedError,
        "Storage must implement #store_execution"
      )
    end
  end

  describe "#store_execution_error" do
    it "raises NotImplementedError" do
      expect { storage.store_execution_error("jid", StandardError.new) }.to raise_error(
        Sidekiq::Tasks::NotImplementedError,
        "Storage must implement #store_execution_error"
      )
    end
  end

  describe "#store_dry_run" do
    it "does nothing by default" do
      expect(storage.store_dry_run("jid")).to be_nil
    end
  end

  describe "#store_execution_report" do
    it "does nothing by default" do
      expect(storage.store_execution_report("jid", {})).to be_nil
    end
  end

  describe "#report_max_bytes" do
    it "returns the configured report_max_bytes, whatever the history_limit" do
      allow(Sidekiq::Tasks.config).to receive(:report_max_bytes).and_return(1024 * 1024)

      expect(described_class.new("foo:bar", history_limit: 1_000).report_max_bytes).to eq(1024 * 1024)
    end
  end
end
