# frozen_string_literal: true

ENV["DUMMY_DB"] = "memory"
require_relative "schema"

RSpec.configure do |config|
  config.before(:all) { DummySchema.load! }
  config.after        { DummySchema.cleanup! }
end
