require "prism"

module Sidekiq
  module Tasks
    module MagicComments
      # A magic comment only applies to the task, desc or namespace call right below it.
      class Scanner
        MAGIC_COMMENT_REGEX = /\A#\s*sidekiq-tasks:([a-z_]+)(?::\s*(.+?))?\s*\z/

        def initialize
          @comments_by_file = {}
        end

        # @return [Comments] From the task to the outermost namespace, so that the closest comment wins.
        def scan(task)
          file, task_line = task.locations.first.split(":")
          @comments_by_file[file] ||= comments_by_task_line(file)

          Comments.new(@comments_by_file[file].fetch(task_line.to_i, []))
        end

        private

        def comments_by_task_line(file)
          parse_result = Prism.parse(read_file(file))
          comment_lines =
            parse_result
            .comments
            .reject(&:trailing?)
            .to_h { |comment| [comment.location.start_line, comment.slice] }

          annotated_calls_by_task_line(parse_result.value).transform_values do |annotated_calls|
            annotated_calls.flat_map { |call, location| magic_comments_above(call, location, comment_lines) }
          end
        end

        def read_file(file)
          File.read(file)
        rescue Errno::ENOENT
          raise Sidekiq::Tasks::ArgumentError, "File '#{file}' not found"
        end

        # Keyed by the line where the task call starts, as recorded by Rake.
        def annotated_calls_by_task_line(node, namespace_calls = [], annotated_calls = {})
          [nil, *node.compact_child_nodes].each_cons(2) do |previous_child, child|
            if rake_call?(child, :task)
              annotated_calls[child.location.start_line] = task_annotated_calls(child, previous_child, namespace_calls)
            elsif rake_call?(child, :namespace)
              annotated_calls_by_task_line(child, [[child, :namespace], *namespace_calls], annotated_calls)
            else
              annotated_calls_by_task_line(child, namespace_calls, annotated_calls)
            end
          end

          annotated_calls
        end

        def task_annotated_calls(task_call, previous_child, namespace_calls)
          desc_calls = rake_call?(previous_child, :desc) ? [[previous_child, :desc]] : []

          [[task_call, :task], *desc_calls, *namespace_calls]
        end

        def rake_call?(node, method_name)
          node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == method_name
        end

        def magic_comments_above(call, location, comment_lines)
          line = call.location.start_line - 1
          magic_comments = []

          while comment_lines.key?(line)
            match = comment_lines[line].match(MAGIC_COMMENT_REGEX)
            magic_comments.unshift(Comment.new(name: match[1], raw_value: match[2], location: location)) if match
            line -= 1
          end

          magic_comments
        end
      end
    end
  end
end
