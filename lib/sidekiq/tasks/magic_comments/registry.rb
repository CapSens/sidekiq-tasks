module Sidekiq
  module Tasks
    module MagicComments
      module Registry
        @handlers = {}

        class << self
          def register(handler)
            @handlers[handler.name_token.to_s] = handler
          end

          def lookup(name)
            @handlers[name.to_s]
          end
        end
      end
    end
  end
end
