module Sidekiq
  module Tasks
    module Storage
      class Redis < Base
        JID_PREFIX = "task".freeze

        # Maximum size of the reports stored in the history of a task, whatever the history_limit.
        TASK_REPORTS_BUDGET = 10 * 1024 * 1024

        def jid_key
          "#{JID_PREFIX}:#{task_name}"
        end

        def history_key
          "#{jid_key}:history"
        end

        def last_enqueue_at
          stored_time("last_enqueue_at")
        end

        def history
          raw_entries = Sidekiq.redis { |conn| conn.lrange(history_key, 0, -1) }

          return [] unless raw_entries

          raw_entries.map do |raw|
            entry = Sidekiq.load_json(raw)
            ["enqueued_at", "executed_at", "finished_at"].each do |key|
              entry[key] = Time.at(entry[key]) if entry[key]
            end
            entry
          end
        end

        def store_history(jid, task_args, time, user: nil)
          Sidekiq.redis do |conn|
            task_trace = {jid: jid, task_name: task_name, args: task_args, enqueued_at: time.to_f}
            task_trace[:user] = user if user
            conn.lpush(history_key, Sidekiq.dump_json(task_trace))
            conn.ltrim(history_key, 0, history_limit - 1)
          end
        end

        def store_enqueue(jid, args, user: nil)
          time = Time.now.to_f
          store_time(time, "last_enqueue_at")
          store_history(jid, args, time, user: user)
        end

        def store_execution(jid, time_key)
          update_history_entry(jid) do |entry|
            entry.merge(time_key => Time.now.to_f)
          end
        end

        def store_execution_error(jid, error)
          update_history_entry(jid) do |entry|
            error_message = truncate_message("#{error.class}: #{error.message}", ERROR_MESSAGE_MAX_LENGTH)
            entry.merge("error" => error_message)
          end
        end

        def store_dry_run(jid)
          update_history_entry(jid) { |entry| entry.merge("dry_run" => true) }
        end

        def store_execution_report(jid, report)
          update_history_entry(jid) { |entry| entry.merge("report" => report) }
        end

        def report_max_bytes
          [super, TASK_REPORTS_BUDGET / history_limit].min
        end

        private

        def store_time(time, time_key)
          Sidekiq.redis { |conn| conn.hset(jid_key, time_key, time.to_f) }
        end

        def stored_time(time_key)
          timestamp = Sidekiq.redis { |conn| conn.hget(jid_key, time_key) }

          [nil, ""].include?(timestamp) ? nil : Time.at(timestamp.to_f)
        end

        def update_history_entry(jid)
          Sidekiq.redis do |conn|
            entries = conn.lrange(history_key, 0, -1)

            entries.each_with_index do |raw, index|
              entry = Sidekiq.load_json(raw)
              next unless entry["jid"] == jid

              updated_entry = yield(entry)
              conn.lset(history_key, index, Sidekiq.dump_json(updated_entry))
              break
            end
          end
        end
      end
    end
  end
end
