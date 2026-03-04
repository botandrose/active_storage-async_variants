# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  minimum_coverage 100
end

RSpec.configure do |config|
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
end

Dir["#{__dir__}/support/**/*.rb"].each { |f| require f }

ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/application"
require "active_storage/async_variants"
require "rspec/rails"

Rails.application.initialize!

ActiveStorage.logger = ActiveSupport::Logger.new(nil)
ActiveStorage.verifier = ActiveSupport::MessageVerifier.new("Testing")

ActiveJob::Base.queue_adapter = :test

RSpec.configure do |config|
  config.include ActiveJob::TestHelper

  config.before do
    ActiveStorage::Current.url_options = { protocol: "https", host: "example.com" }
  end

  config.after do
    ActiveStorage::Current.reset
  end
end
