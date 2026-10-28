module Sidekiq
  module Tasks
    module MagicComments
      class Comments
        include Enumerable

        def initialize(list = [])
          @list = list
        end

        def each(&block)
          @list.each(&block)
        end

        def any?(name)
          @list.any? { |comment| comment.name == name.to_s }
        end

        def fetch(name, default: nil)
          comment = @list.find { |c| c.name == name.to_s }
          return default unless comment

          handler = Registry.lookup(name)
          return comment.raw_value unless handler

          handler.cast(comment.raw_value)
        end
      end
    end
  end
end
