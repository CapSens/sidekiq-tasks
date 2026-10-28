require "spec_helper"

RSpec.describe Sidekiq::Tasks::MagicComments::Comment do
  describe "#initialize" do
    it "stores the attributes", :aggregate_failures do
      comment = described_class.new(name: "enable", location: :task, raw_value: nil)

      expect(comment.name).to eq("enable")
      expect(comment.location).to eq(:task)
      expect(comment.raw_value).to be_nil
    end

    it "coerces name to a String" do
      comment = described_class.new(name: :enable, location: :task)

      expect(comment.name).to eq("enable")
    end

    it "raises when location is not valid" do
      expect { described_class.new(name: "enable", location: :invalid) }.to raise_error(
        Sidekiq::Tasks::ArgumentError,
        /location/
      )
    end
  end
end
