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

        def execution_key(jid)
          "#{jid_key}:execution:#{jid}"
        end

        def last_enqueue_at
          stored_time("last_enqueue_at")
        end

        def history
          entries = Sidekiq.redis { |conn| conn.lrange(history_key, 0, -1) }.map { |raw| Sidekiq.load_json(raw) }

          return [] if entries.empty?

          entries.zip(executions(entries)).map { |entry, execution| parse_entry(entry.merge(execution)) }
        end

        def store_history(jid, task_args, time, user: nil)
          Sidekiq.redis do |conn|
            task_trace = {jid: jid, task_name: task_name, args: task_args, enqueued_at: time.to_f}
            task_trace[:user] = user if user
            conn.lpush(history_key, Sidekiq.dump_json(task_trace))
            delete_executions(conn, conn.lrange(history_key, history_limit, -1))
            conn.ltrim(history_key, 0, history_limit - 1)
          end
        end

        def store_enqueue(jid, args, user: nil)
          time = Time.now.to_f
          store_time(time, "last_enqueue_at")
          store_history(jid, args, time, user: user)
        end

        def store_execution(jid, time_key)
          Sidekiq.redis { |conn| conn.hset(execution_key(jid), time_key, Time.now.to_f) }
        end

        def store_execution_error(jid, error)
          error_message = truncate_message("#{error.class}: #{error.message}", ERROR_MESSAGE_MAX_LENGTH)
          Sidekiq.redis { |conn| conn.hset(execution_key(jid), "error", error_message) }
        end

        def store_dry_run(jid)
          Sidekiq.redis { |conn| conn.hset(execution_key(jid), "dry_run", Sidekiq.dump_json(true)) }
        end

        def store_execution_report(jid, report)
          Sidekiq.redis { |conn| conn.hset(execution_key(jid), "report", Sidekiq.dump_json(report)) }
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

        def executions(entries)
          Sidekiq.redis do |conn|
            conn.pipelined do |pipeline|
              entries.each { |entry| pipeline.hgetall(execution_key(entry["jid"])) }
            end
          end
        end

        def parse_entry(entry)
          ["enqueued_at", "executed_at", "finished_at"].each do |key|
            entry[key] = Time.at(entry[key].to_f) if entry[key]
          end
          ["dry_run", "report"].each do |key|
            entry[key] = Sidekiq.load_json(entry[key]) if entry[key]
          end

          entry
        end

        def delete_executions(conn, raw_entries)
          return if raw_entries.empty?

          conn.del(*raw_entries.map { |raw| execution_key(Sidekiq.load_json(raw)["jid"]) })
        end
      end
    end
  end
end
