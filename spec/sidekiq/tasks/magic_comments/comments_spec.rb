require "spec_helper"

RSpec.describe Sidekiq::Tasks::MagicComments::Comments do
  let(:enable_comment) { Sidekiq::Tasks::MagicComments::Comment.new(name: "enable", location: :task) }
  let(:custom_comment) do
    Sidekiq::Tasks::MagicComments::Comment.new(
      name: "custom_unknown",
      location: :task,
      raw_value: "raw"
    )
  end

  describe "#any?" do
    it "returns true when a comment with the given name exists" do
      comments = described_class.new([enable_comment])

      expect(comments.any?("enable")).to be(true)
    end

    it "returns false when no comment matches" do
      comments = described_class.new([enable_comment])

      expect(comments.any?("disable")).to be(false)
    end

    it "accepts symbols" do
      comments = described_class.new([enable_comment])

      expect(comments.any?(:enable)).to be(true)
    end
  end

  describe "#fetch" do
    it "returns the casted value when a registered handler exists" do
      comments = described_class.new([enable_comment])

      expect(comments.fetch("enable")).to be(true)
    end

    it "returns the raw_value when no handler is registered" do
      comments = described_class.new([custom_comment])

      expect(comments.fetch("custom_unknown")).to eq("raw")
    end

    it "returns the default when the comment is absent" do
      comments = described_class.new([])

      expect(comments.fetch("missing", default: {foo: 1})).to eq({foo: 1})
    end
  end

  describe "#each" do
    it "iterates over comments" do
      comments = described_class.new([enable_comment, custom_comment])

      expect(comments.to_a).to eq([enable_comment, custom_comment])
    end
  end
end
