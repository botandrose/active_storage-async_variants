# frozen_string_literal: true

RSpec.describe "async variants: heartbeat watchdog" do
  include_context "with an attached avatar"

  def watch(record)
    ActiveStorage::AsyncVariants::HeartbeatWatchdogJob.perform_now(record)
  end

  it "fails a record whose heartbeat has gone stale" do
    variant = @user.avatar.variant(:thumb)
    record = create_variant_record(variant, state: "processing")
    record.update!(last_heartbeat_at: 5.minutes.ago)

    watch(record)

    record.reload
    expect(record.state).to eq("failed")
    expect(record.error).to match(/stalled/i)
  end

  it "re-arms itself while the record is active and the heartbeat is fresh" do
    variant = @user.avatar.variant(:thumb)
    record = create_variant_record(variant, state: "processing")
    record.update!(last_heartbeat_at: Time.current)

    expect { watch(record) }
      .to have_enqueued_job(ActiveStorage::AsyncVariants::HeartbeatWatchdogJob)
    expect(record.reload.state).to eq("processing")
  end

  it "stops once the record reaches a terminal state" do
    variant = @user.avatar.variant(:thumb)
    record = create_variant_record(variant, state: "processed")
    record.update!(last_heartbeat_at: 5.minutes.ago)

    expect { watch(record) }
      .not_to have_enqueued_job(ActiveStorage::AsyncVariants::HeartbeatWatchdogJob)
    expect(record.reload.state).to eq("processed")
  end
end
