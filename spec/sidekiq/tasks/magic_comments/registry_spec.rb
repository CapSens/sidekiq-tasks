require "spec_helper"

RSpec.describe Sidekiq::Tasks::MagicComments::Registry do
  describe ".lookup" do
    it "returns the handler registered for a name" do
      expect(described_class.lookup("enable")).to eq(Sidekiq::Tasks::MagicComments::Handlers::Enable)
    end

    it "accepts symbols and looks them up as strings" do
      expect(described_class.lookup(:disable)).to eq(Sidekiq::Tasks::MagicComments::Handlers::Disable)
    end

    it "returns nil for unknown handlers" do
      expect(described_class.lookup("unknown_thing")).to be_nil
    end
  end

  describe ".register" do
    it "stores a handler keyed by its name_token", :aggregate_failures do
      handler = Class.new(Sidekiq::Tasks::MagicComments::Handlers::Base) do
        def self.name_token = "registry_spec_handler"
        def self.cast(_raw_value) = "ok"
      end

      described_class.register(handler)

      expect(described_class.lookup("registry_spec_handler")).to eq(handler)
    end
  end
end
