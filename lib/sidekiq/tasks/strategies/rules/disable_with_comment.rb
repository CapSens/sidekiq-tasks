module Sidekiq
  module Tasks
    module Strategies
      module Rules
        class DisableWithComment < EnableWithComment
          def respected?(task)
            !super
          end

          protected

          def magic_comment_token
            Sidekiq::Tasks::MagicComments::Handlers::Disable.name_token
          end
        end
      end
    end
  end
end
