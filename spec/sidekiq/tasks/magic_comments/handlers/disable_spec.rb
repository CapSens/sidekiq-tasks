require "spec_helper"

RSpec.describe Sidekiq::Tasks::MagicComments::Handlers::Disable do
  describe ".name_token" do
    it { expect(described_class.name_token).to eq("disable") }
  end

  describe ".cast" do
    it "always returns true" do
      expect(described_class.cast(nil)).to be(true)
      expect(described_class.cast("anything")).to be(true)
    end
  end
end
