# frozen_string_literal: true

require_relative "lib/sidekiq/tasks/version"

Gem::Specification.new do |spec|
  spec.name = "sidekiq-tasks"
  spec.version = Sidekiq::Tasks::VERSION
  spec.authors = ["Capsens"]
  spec.email = ["contact@capsens.eu"]
  spec.summary = "Sidekiq extension for launching tasks."
  spec.description = <<~DESC
    Sidekiq Tasks is an extension for Sidekiq that provides an interface for launching tasks.
    Natively supports rake tasks and can be easily extended to support other task execution systems.
  DESC

  spec.homepage = "https://github.com/CapSens/sidekiq-tasks"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/blob/master"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Ruby parser, used to read the magic comments of rake files.
  spec.add_runtime_dependency "prism", "~> 1.5"
  spec.add_runtime_dependency "rake", ">= 13.0"
  spec.add_runtime_dependency "sidekiq", ">= 6.5"

  spec.add_development_dependency "base64"
  spec.add_development_dependency "capybara"
  spec.add_development_dependency "rack-session"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "rackup"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "selenium-webdriver"
  spec.add_development_dependency "sidekiq"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "simplecov-json"
  spec.add_development_dependency "webrick"
end
