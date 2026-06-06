# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Run browser-level acceptance tests (cucumber + cuprite against spec/dummy)"
task :cucumber do
  sh "bundle exec cucumber"
end

desc "Run rspec and cucumber"
task all: [:spec, :cucumber]

task default: :all
