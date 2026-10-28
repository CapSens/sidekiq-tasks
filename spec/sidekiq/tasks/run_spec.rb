require "spec_helper"

RSpec.describe Sidekiq::Tasks::Run do
  describe ".with" do
    it "makes the run current during the block and restores the previous one", :aggregate_failures do
      outer_run = described_class.new
      inner_run = described_class.new(dry_run: true)

      described_class.with(outer_run) do
        described_class.with(inner_run) { expect(described_class.current).to eq(inner_run) }
        expect(described_class.current).to eq(outer_run)
      end

      expect(Thread.current[described_class::THREAD_KEY]).to be_nil
    end

    it "restores the previous run when the block raises" do
      expect { described_class.with(described_class.new) { raise "boom" } }.to raise_error("boom")
      expect(Thread.current[described_class::THREAD_KEY]).to be_nil
    end
  end

  describe ".current" do
    before { described_class.instance_variable_set(:@_standalone, nil) }

    it "returns a memoized standalone run, printing its report on exit, outside of a job", :aggregate_failures do
      exit_hook = nil
      allow(described_class).to receive(:at_exit) { |&block| exit_hook = block }

      run = described_class.current
      run.report.increment(:success)

      expect(run.dry_run?).to eq(false)
      expect(described_class.current).to eq(run)
      expect { exit_hook.call }.to output(/"success": 1/).to_stdout
    end
  end

  describe "#dry_run?" do
    it "returns the dry run mode", :aggregate_failures do
      expect(described_class.new.dry_run?).to eq(false)
      expect(described_class.new(dry_run: true).dry_run?).to eq(true)
    end
  end
end

RSpec.describe Sidekiq::Tasks::Report do
  it "is empty by default" do
    expect(described_class.new).to be_empty
  end

  it "stores values and counters" do
    report = described_class.new
    report[:total] = 3
    report.increment(:success)
    report.increment(:success, 2)

    expect(report.to_h).to eq({"values" => {"total" => 3, "success" => 3}, "lists" => {}})
  end

  it "stores non finite floats as strings to keep the report serializable" do
    report = described_class.new
    report[:ratio] = 0 / 0.0
    report.increment(:duration, Float::INFINITY)
    report.add(:rows, {ratio: -Float::INFINITY})

    expect(report.to_h).to eq(
      {
        "values" => {"ratio" => "NaN", "duration" => "Infinity"},
        "lists" => {"rows" => {"items" => [{"ratio" => "-Infinity"}], "count" => 1}},
      }
    )
  end

  it "keeps list items with an exact count" do
    report = described_class.new
    3.times { |index| report.add(:failed, {id: index}) }

    expect(report.to_h["lists"]).to eq({"failed" => {"items" => [{"id" => 0}, {"id" => 1}, {"id" => 2}], "count" => 3}})
  end

  describe "Redis memory protection" do
    it "truncates strings and converts nested structures to strings", :aggregate_failures do
      report = described_class.new
      report[:message] = "a" * 1000
      report.add(:failed, {id: 1, errors: ["foo", "bar"], details: {"a" => "b" * 1000}})

      value = report.to_h["values"]["message"]
      item = report.to_h["lists"]["failed"]["items"].first

      expect(value.length).to eq(described_class::MAX_STRING_LENGTH)
      expect(value).to end_with("...")
      expect(item["id"]).to eq(1)
      expect(item["errors"]).to eq(["foo", "bar"].to_s)
      expect(item["details"].length).to eq(described_class::MAX_STRING_LENGTH)
    end

    it "ignores keys beyond MAX_KEYS and flags the report as truncated", :aggregate_failures do
      report = described_class.new
      (described_class::MAX_KEYS + 1).times do |index|
        report.increment("value_#{index}")
        report.add("list_#{index}", index)
      end
      report.increment("value_0")

      expect(report.to_h["values"].size).to eq(described_class::MAX_KEYS)
      expect(report.to_h["lists"].size).to eq(described_class::MAX_KEYS)
      expect(report.to_h["values"]["value_0"]).to eq(2)
      expect(report.to_h["truncated"]).to eq(true)
    end

    it "drops the last items of the longest lists to fit in max_bytes, keeping exact counts", :aggregate_failures do
      report = described_class.new(max_bytes: 2_000)
      report[:total] = 300
      200.times { |index| report.add(:failed, {id: index, error: "Invalid email"}) }
      100.times { |index| report.add(:skipped, index) }

      hash = report.to_h

      expect(Sidekiq.dump_json(hash).bytesize).to be <= 2_000
      expect(hash["values"]).to eq({"total" => 300})
      expect(hash["lists"]["failed"]["count"]).to eq(200)
      expect(hash["lists"]["failed"]["items"].first).to eq({"id" => 0, "error" => "Invalid email"})
      expect(hash["lists"]["skipped"]["count"]).to eq(100)
      expect(hash["truncated"]).to eq(true)
    end

    it "does not alter the report itself when fitting it", :aggregate_failures do
      report = described_class.new(max_bytes: 200)
      50.times { |index| report.add(:failed, index) }

      report.to_h

      expect(report.to_h["lists"]["failed"]["items"]).not_to be_empty
      expect(report.instance_variable_get(:@lists)["failed"]["items"].size).to eq(50)
    end

    it "defaults max_bytes to the configured report_max_bytes" do
      allow(Sidekiq::Tasks.config).to receive(:report_max_bytes).and_return(500)
      report = described_class.new
      100.times { |index| report.add(:failed, "item #{index}") }

      expect(Sidekiq.dump_json(report.to_h).bytesize).to be <= 500
    end

    it "stops keeping items beyond MEMORY_FACTOR times max_bytes while counting them", :aggregate_failures do
      report = described_class.new(max_bytes: 1_000)
      1_000.times { |index| report.add(:failed, "x" * 100 + index.to_s) }

      kept_items = report.instance_variable_get(:@lists)["failed"]["items"]
      expect(kept_items.sum { |item| Sidekiq.dump_json(item).bytesize }).to be <= (1_000 * described_class::MEMORY_FACTOR) + 200
      expect(kept_items.size).to be < 1_000
      expect(report.to_h["lists"]["failed"]["count"]).to eq(1_000)
      expect(report.to_h["truncated"]).to eq(true)
    end

    it "falls back to an empty truncated report when values alone exceed max_bytes" do
      report = described_class.new(max_bytes: 10)
      report[:message] = "too long for the limit"

      expect(report.to_h).to eq({"values" => {}, "lists" => {}, "truncated" => true})
    end

    it "does not flag a report within limits as truncated" do
      report = described_class.new
      report.increment(:success)

      expect(report.to_h).not_to have_key("truncated")
    end
  end
end
