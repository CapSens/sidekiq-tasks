module Sidekiq
  module Tasks
    module Strategies
      module Rules
        class EnableWithComment < Base
          def initialize(scanner: Sidekiq::Tasks::MagicComments::Scanner.new)
            super()
            @scanner = scanner
          end

          def respected?(task)
            @scanner.scan(task).any?(magic_comment_token)
          end

          protected

          def magic_comment_token
            Sidekiq::Tasks::MagicComments::Handlers::Enable.name_token
          end
        end
      end
    end
  end
end
