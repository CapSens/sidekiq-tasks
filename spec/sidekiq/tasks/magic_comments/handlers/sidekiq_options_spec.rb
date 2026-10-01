require "spec_helper"

RSpec.describe Sidekiq::Tasks::MagicComments::Handlers::SidekiqOptions do
  describe ".name_token" do
    it { expect(described_class.name_token).to eq("sidekiq_options") }
  end

  describe ".cast" do
    it "returns an empty Hash when raw_value is nil" do
      expect(described_class.cast(nil)).to eq({})
    end

    it "returns an empty Hash when raw_value is blank" do
      expect(described_class.cast("   ")).to eq({})
    end

    it "parses a single key-value pair" do
      expect(described_class.cast("queue: critical")).to eq(queue: "critical")
    end

    it "parses multiple key-value pairs", :aggregate_failures do
      result = described_class.cast("queue: critical, retry: 5")

      expect(result).to eq(queue: "critical", retry: 5)
    end

    it "parses an array value" do
      expect(described_class.cast("tags: [daily, critical]")).to eq(tags: ["daily", "critical"])
    end

    it "raises when YAML is invalid" do
      expect { described_class.cast("queue: 'unterminated") }.to raise_error(
        Sidekiq::Tasks::ArgumentError,
        /not valid YAML/
      )
    end

    it "accepts a partial hash (no queue required)" do
      expect(described_class.cast("retry: 3")).to eq(retry: 3)
    end

    it "accepts unknown keys without raising" do
      expect(described_class.cast("whatever: yolo")).to eq(whatever: "yolo")
    end

    it "passes middleware options such as sidekiq-unique-jobs locks" do
      expect(described_class.cast("queue: low, lock: until_executed")).to eq(queue: "low", lock: "until_executed")
    end

    it "rejects supported keys with an invalid type", :aggregate_failures do
      expect { described_class.cast("retry: abc") }.to raise_error(
        Sidekiq::Tasks::ArgumentError,
        "'retry' must be an instance of NilClass or TrueClass or FalseClass or Integer but received String"
      )
      expect { described_class.cast("queue: 42") }.to raise_error(Sidekiq::Tasks::ArgumentError, /'queue' must be an instance of String/)
    end
  end
end
