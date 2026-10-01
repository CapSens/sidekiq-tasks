module Sidekiq
  module Tasks
    module MagicComments
      class Scanner
        MAGIC_COMMENT_REGEX = /\A#\s*sidekiq-tasks:([a-z_]+)(?::\s*(.+?))?\s*\z/
        TASK_CONTEXT_LINES = 3

        def scan(task)
          file, task_line = task.locations.first.split(":")
          task_line = task_line.to_i

          lines = read_file_lines(file)
          captured = {}

          capture_namespace_comment(lines, task, captured)
          capture_desc_comment(lines, task_line, task.full_comment, captured)
          capture_task_comments(lines, task_line, captured)

          Comments.new(captured.values)
        end

        private

        def read_file_lines(file)
          File.read(file).split("\n")
        rescue Errno::ENOENT
          raise Sidekiq::Tasks::ArgumentError, "File '#{file}' not found"
        end

        def capture_namespace_comment(lines, task, captured)
          namespace = task.name.split(":").first
          namespace_line_index = lines.find_index do |line|
            line.strip.match?(/^namespace\s+:#{Regexp.escape(namespace)}/)
          end
          return unless namespace_line_index

          capture_comment_block(lines, namespace_line_index - 1, :namespace, captured)
        end

        def capture_desc_comment(lines, task_line, desc, captured)
          return unless desc

          desc_line_index = lines[0...task_line].rindex { |line| line.strip.match?(/^desc\b/) }
          return unless desc_line_index

          capture_comment_block(lines, desc_line_index - 1, :desc, captured)
        end

        def capture_task_comments(lines, task_line, captured)
          ((task_line - TASK_CONTEXT_LINES)..task_line).each do |i|
            next if i.negative?
            next if captured.key?(i)

            capture_at_index(lines, i, :task, captured)
          end
        end

        def capture_comment_block(lines, index, location, captured)
          index.downto(0) do |i|
            break unless lines[i].strip.start_with?("#")

            capture_at_index(lines, i, location, captured) unless captured.key?(i)
          end
        end

        def capture_at_index(lines, index, location, captured)
          return if index.negative?

          line = lines[index]&.strip
          return unless line

          match = line.match(MAGIC_COMMENT_REGEX)
          return unless match

          captured[index] = Comment.new(name: match[1], raw_value: match[2], location: location)
        end
      end
    end
  end
end
