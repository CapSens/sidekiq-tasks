require "spec_helper"

RSpec.describe Sidekiq::Tasks::SidekiqOptionsValidator do
  describe ".validate!" do
    context "in strict mode (default)" do
      it "passes for a valid full hash" do
        full_options = {queue: "low", retry: false, dead: true, backtrace: true, pool: "p", tags: ["a"]}
        expect { described_class.validate!(full_options) }.not_to raise_error
      end

      it "raises when options is not a Hash" do
        expect { described_class.validate!("foo") }.to raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'sidekiq_options' must be an instance of Hash but received String"
        )
      end

      it "raises when queue is missing (required)" do
        expect { described_class.validate!({retry: 5}) }.to raise_error(
          Sidekiq::Tasks::ArgumentError,
          "'queue' must be an instance of String but received NilClass"
        )
      end

      it "raises when retry has an invalid type" do
        expect { described_class.validate!({queue: "low", retry: "nope"}) }.to raise_error(
          Sidekiq::Tasks::ArgumentError,
          /'retry' must be an instance of/
        )
      end

      it "accepts unknown keys" do
        expect { described_class.validate!({queue: "low", foo: "bar"}) }.not_to raise_error
      end
    end

    context "with allow_partial: true" do
      it "accepts an empty hash" do
        expect { described_class.validate!({}, allow_partial: true) }.not_to raise_error
      end

      it "accepts only retry without queue" do
        expect { described_class.validate!({retry: 5}, allow_partial: true) }.not_to raise_error
      end

      it "still validates types of present keys" do
        expect { described_class.validate!({queue: 123}, allow_partial: true) }.to raise_error(
          Sidekiq::Tasks::ArgumentError,
          /'queue' must be an instance of String/
        )
      end

      it "accepts unknown keys" do
        expect { described_class.validate!({foo: "bar"}, allow_partial: true) }.not_to raise_error
      end
    end
  end
end
