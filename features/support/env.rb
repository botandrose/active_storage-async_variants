# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../../spec/dummy/config/environment", __dir__)

require "capybara"
require "capybara/cucumber"
require "capybara/cuprite"
require_relative "../../spec/support/schema"

DummySchema.load!

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1200, 900], timeout: 10, process_timeout: 20, js_errors: true)
end
Capybara.app                = Rails.application
Capybara.javascript_driver  = :cuprite
Capybara.default_driver     = :cuprite
Capybara.server             = :puma, { Silent: true }

ActionController::Base.allow_forgery_protection = false

# Test adapter just records enqueued jobs -- we don't want them to actually run
# during browser tests (they'd call real transformers and modify variant_records
# behind the test's back). The retry step seeds the new state explicitly.
ActiveJob::Base.queue_adapter = :test

Before { DummySchema.cleanup! }
