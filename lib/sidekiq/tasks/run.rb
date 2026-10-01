module Sidekiq
  module Tasks
    # The context of a task execution, available from the task code through `Sidekiq::Tasks.current_run`.
    class Run
      THREAD_KEY = :sidekiq_tasks_run

      attr_reader :report

      # Outside of a Sidekiq::Tasks job (e.g. `rake` in a terminal), dry run is disabled
      # and the report is printed on exit.
      def self.current
        Thread.current[THREAD_KEY] || standalone
      end

      def self.with(run)
        previous_run = Thread.current[THREAD_KEY]
        Thread.current[THREAD_KEY] = run
        yield
      ensure
        Thread.current[THREAD_KEY] = previous_run
      end

      def self.standalone
        @_standalone ||= new.tap do |run|
          at_exit { puts JSON.pretty_generate(run.report.to_h) unless run.report.empty? }
        end
      end
      private_class_method :standalone

      def initialize(dry_run: false, report_max_bytes: Sidekiq::Tasks.config.report_max_bytes)
        @dry_run = dry_run
        @report = Report.new(max_bytes: report_max_bytes)
      end

      def dry_run?
        @dry_run
      end
    end

    # A structured execution report, stored in the task history and displayed in the web interface.
    #
    # The report size is bounded by `max_bytes`, see Sidekiq::Tasks::Storage::Base#report_max_bytes:
    # - the serialized report never exceeds `max_bytes`, the last items of the longest lists are dropped
    #   and the counts remain exact,
    # - while the task runs, items stop being kept beyond MEMORY_FACTOR times that size, protecting worker memory,
    # - strings are truncated to MAX_STRING_LENGTH, so that a single long message does not fill the whole report,
    # - at most MAX_KEYS values, lists and item keys, guarding against keys built from the data.
    class Report
      MAX_KEYS = 50
      MAX_STRING_LENGTH = 255
      MEMORY_FACTOR = 4

      def initialize(max_bytes: Sidekiq::Tasks.config.report_max_bytes)
        @max_bytes = max_bytes
        @kept_bytes = 0
        @values = {}
        @lists = {}
        @truncated = false
      end

      def []=(key, value)
        key = sanitize_key(key)
        @values[key] = sanitize_scalar(value) if accept_key?(@values, key)
      end

      def increment(key, by = 1)
        key = sanitize_key(key)
        @values[key] = (@values[key] || 0) + by if accept_key?(@values, key)
      end

      # Adds an item (a scalar or a flat Hash) to a list.
      def add(key, item)
        key = sanitize_key(key)
        return unless accept_key?(@lists, key)

        list = @lists[key] ||= {"items" => [], "count" => 0}
        list["count"] += 1
        keep_item(list, sanitize_item(item))
      end

      def empty?
        @values.empty? && @lists.empty?
      end

      # @return [Hash] The report, serializable as JSON and at most `max_bytes` long.
      def to_h
        lists = @lists.transform_values { |list| list.merge("items" => list["items"].dup) }
        report = {"values" => @values, "lists" => lists}
        report["truncated"] = true if @truncated
        return report if Sidekiq.dump_json(report).bytesize <= @max_bytes

        fit(report.merge("truncated" => true))
      end

      private

      # Falls back to an empty report when values alone exceed max_bytes.
      def fit(report)
        drop_items(report, Sidekiq.dump_json(report).bytesize)
        return report if Sidekiq.dump_json(report).bytesize <= @max_bytes

        {"values" => {}, "lists" => {}, "truncated" => true}
      end

      # Sizes are tracked incrementally so that the report is not serialized again for each dropped item.
      def drop_items(report, size)
        lists = report["lists"].values

        while size > @max_bytes
          longest_list = lists.max_by { |list| list["items"].size }
          break if longest_list.nil? || longest_list["items"].empty?

          size -= Sidekiq.dump_json(longest_list["items"].pop).bytesize + 1
        end
      end

      # Items are kept with a margin over max_bytes so that to_h can still balance the lists,
      # but never beyond it, so that the worker memory stays bounded.
      def keep_item(list, item)
        if @kept_bytes > @max_bytes * MEMORY_FACTOR
          @truncated = true
          return
        end

        @kept_bytes += Sidekiq.dump_json(item).bytesize
        list["items"] << item
      end

      def accept_key?(hash, key)
        return true if hash.key?(key) || hash.size < MAX_KEYS

        @truncated = true
        false
      end

      def sanitize_key(key)
        truncate(key.to_s)
      end

      def sanitize_item(item)
        return sanitize_scalar(item) unless item.is_a?(Hash)

        item.first(MAX_KEYS).to_h { |key, value| [sanitize_key(key), sanitize_scalar(value)] }
      end

      def sanitize_scalar(value)
        case value
        when Numeric, TrueClass, FalseClass, NilClass then value
        else truncate(value.to_s)
        end
      end

      def truncate(string)
        return string if string.length <= MAX_STRING_LENGTH

        "#{string[0...(MAX_STRING_LENGTH - 3)]}..."
      end
    end
  end
end
