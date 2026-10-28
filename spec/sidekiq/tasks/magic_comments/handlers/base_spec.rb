require "spec_helper"

RSpec.describe Sidekiq::Tasks::MagicComments::Handlers::Base do
  it "raises NotImplementedError on .name_token" do
    expect { described_class.name_token }.to raise_error(Sidekiq::Tasks::NotImplementedError)
  end

  it "raises NotImplementedError on .cast" do
    expect { described_class.cast("foo") }.to raise_error(Sidekiq::Tasks::NotImplementedError)
  end
end
