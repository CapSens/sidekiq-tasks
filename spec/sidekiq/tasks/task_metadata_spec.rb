require "spec_helper"

RSpec.describe Sidekiq::Tasks::TaskMetadata do
  describe "validations" do
    it "accepts a symbol or string as name", :aggregate_failures do
      expect(build_task_metadata(name: "foo").name).to eq("foo")
      expect(build_task_metadata(name: :foo).name).to eq(:foo)
      expect { build_task_metadata(name: 1) }.to raise_error(Sidekiq::Tasks::ArgumentError)
    end

    it "accepts a string or nil as desc", :aggregate_failures do
      expect(build_task_metadata(desc: "foo").desc).to eq("foo")
      expect(build_task_metadata(desc: nil).desc).to be_nil
      expect { build_task_metadata(desc: 1) }.to raise_error(Sidekiq::Tasks::ArgumentError)
    end

    it "accepts a string or nil as file", :aggregate_failures do
      expect(build_task_metadata(file: "foo.rb").file).to eq("foo.rb")
      expect(build_task_metadata(file: nil).file).to be_nil
      expect { build_task_metadata(file: 1) }.to raise_error(Sidekiq::Tasks::ArgumentError)
    end

    it "accepts an array of strings or symbols as args", :aggregate_failures do
      expect(build_task_metadata(args: ["foo"]).args).to eq(["foo"])
      expect(build_task_metadata(args: [:foo]).args).to eq([:foo])
      expect { build_task_metadata(args: [1]) }.to raise_error(Sidekiq::Tasks::ArgumentError)
    end

    it "accepts any Hash as sidekiq_options", :aggregate_failures do
      expect(build_task_metadata(sidekiq_options: {}).sidekiq_options).to eq({})
      expect(build_task_metadata(sidekiq_options: {queue: "low"}).sidekiq_options).to eq({queue: "low"})
      expect(build_task_metadata(sidekiq_options: {whatever: "yolo"}).sidekiq_options).to eq({whatever: "yolo"})
      expect { build_task_metadata(sidekiq_options: "foo") }.to raise_error(Sidekiq::Tasks::ArgumentError)
    end

    it "accepts a boolean as dry_run", :aggregate_failures do
      expect(build_task_metadata.dry_run?).to eq(false)
      expect(build_task_metadata(dry_run: true).dry_run?).to eq(true)
      expect { build_task_metadata(dry_run: "true") }.to raise_error(Sidekiq::Tasks::ArgumentError)
    end

    it "accepts a string or nil as error", :aggregate_failures do
      expect(build_task_metadata(error: nil).error).to be_nil
      expect(build_task_metadata(error: "boom").error).to eq("boom")
      expect { build_task_metadata(error: 1) }.to raise_error(Sidekiq::Tasks::ArgumentError)
    end

    it "skips sidekiq_options and args validation when error is present" do
      expect do
        build_task_metadata(error: "boom", sidekiq_options: "not a hash", args: [1])
      end.not_to raise_error
    end
  end

  describe "#error?" do
    it "returns true when error is present" do
      expect(build_task_metadata(error: "boom").error?).to be(true)
    end

    it "returns false when error is nil" do
      expect(build_task_metadata.error?).to be(false)
    end
  end

  describe "readers" do
    it "has name, desc, file, args and sidekiq_options", :aggregate_failures do
      metadata = build_task_metadata(
        name: "foo", file: "foo.rb", desc: "foo", args: ["bar"], sidekiq_options: {retry: 5}
      )
      expect(metadata.name).to eq("foo")
      expect(metadata.desc).to eq("foo")
      expect(metadata.file).to eq("foo.rb")
      expect(metadata.args).to eq(["bar"])
      expect(metadata.sidekiq_options).to eq({retry: 5})
    end

    it "defaults sidekiq_options to an empty hash" do
      expect(build_task_metadata.sidekiq_options).to eq({})
    end
  end
end
