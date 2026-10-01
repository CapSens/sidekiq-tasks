module FactoryHelper
  def build_strategy(rules: [])
    FakeStrategy.new(rules: rules)
  end

  def build_task_set(*tasks)
    Sidekiq::Tasks::Set.new(tasks || [])
  end

  def build_task(name: "foo", file: nil, desc: nil, args: [], sidekiq_options: {}, error: nil, dry_run: false, strategy: nil, metadata: nil)
    Sidekiq::Tasks::Task.new(
      metadata: metadata || build_task_metadata(
        name: name, file: file, desc: desc, args: args, sidekiq_options: sidekiq_options, error: error, dry_run: dry_run
      ),
      strategy: strategy || Sidekiq::Tasks::Strategies::RakeTask.new
    )
  end

  def build_task_metadata(name: "foo", file: nil, desc: nil, args: [], sidekiq_options: {}, error: nil, dry_run: false)
    Sidekiq::Tasks::TaskMetadata.new(
      name: name, file: file, desc: desc, args: args, sidekiq_options: sidekiq_options, error: error, dry_run: dry_run
    )
  end

  def build_strategy_rule(&block)
    Class.new(Sidekiq::Tasks::Strategies::Rules::Base, &block).new
  end

  def build_rake_task(name: "foo:bar", full_comment: "Bar", locations: ["foo.rb:2"], arg_names: ["bar"])
    instance_double(Rake::Task, name: name, full_comment: full_comment, locations: locations, arg_names: arg_names)
  end
end
