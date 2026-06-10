# frozen_string_literal: true

RSpec.describe "async variants: configuration" do
  around do |example|
    previous_interval = ActiveStorage::AsyncVariants.heartbeat_interval
    previous_stale = ActiveStorage::AsyncVariants.heartbeat_stale_after
    example.run
    ActiveStorage::AsyncVariants.heartbeat_interval = previous_interval
    ActiveStorage::AsyncVariants.heartbeat_stale_after = previous_stale
  end

  it "yields the module so options can be set in one block" do
    ActiveStorage::AsyncVariants.configure do |config|
      config.heartbeat_interval = 9.seconds
      config.heartbeat_stale_after = 99.seconds
    end

    expect(ActiveStorage::AsyncVariants.heartbeat_interval).to eq(9.seconds)
    expect(ActiveStorage::AsyncVariants.heartbeat_stale_after).to eq(99.seconds)
  end
end
