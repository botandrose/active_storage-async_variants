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

namespace :vendor do
  desc "Pull the latest @botandrose/progress-bar from unpkg.com into app/assets"
  task :progress_bar do
    require "open-uri"
    url = "https://unpkg.com/@botandrose/progress-bar"
    dest = File.expand_path("app/assets/javascripts/progress-bar.js", __dir__)
    File.write(dest, URI.open(url).read)
    puts "Vendored #{url} -> #{dest}"
  end
end

task default: :all
