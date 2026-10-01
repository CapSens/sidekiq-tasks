module Sidekiq
  module Tasks
    class TaskMetadata
      include Sidekiq::Tasks::Validations

      attr_reader :name, :desc, :file, :args, :sidekiq_options, :error, :dry_run

      def initialize(name:, file:, desc: "", args: [], sidekiq_options: {}, error: nil, dry_run: false)
        @name = name
        @file = file
        @desc = desc
        @args = args
        @sidekiq_options = sidekiq_options
        @error = error
        @dry_run = dry_run

        validate_params!
      end

      def error?
        !@error.nil?
      end

      def dry_run?
        @dry_run
      end

      private

      def validate_params!
        validate_class!(name, [String, Symbol], "name")
        validate_class!(file, [String, NilClass], "file")
        validate_class!(error, [String, NilClass], "error")
        return if error?

        validate_class!(desc, [String, NilClass], "desc")
        validate_array_classes!(args, [String, Symbol], "args")
        validate_class!(sidekiq_options, [Hash], "sidekiq_options")
        validate_class!(dry_run, [TrueClass, FalseClass], "dry_run")
      end
    end
  end
end
