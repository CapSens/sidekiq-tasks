module Sidekiq
  module Tasks
    module Web
      module Helpers
        module TagHelper
          extend self

          def build_tag(tag, content = nil, **attributes, &block)
            attr_string = attributes.map { |key, value| "#{key}=\"#{ERB::Util.html_escape(value)}\"" }.join(" ")
            attr_string = " #{attr_string}" unless attr_string.empty?

            "<#{tag}#{attr_string}>#{block&.call || content}</#{tag}>"
          end

          def build_classes(*classes, **conditions)
            condition_classes = conditions.select { |_, value| value }.keys

            (classes + condition_classes).join(" ")
          end
        end
      end
    end
  end
end
