# frozen_string_literal: true

RSpec.describe "async variants: processing jobs" do
  include_context "with an attached avatar"

  describe "default transformer (no transformer: option)" do
    it "processes the variant using standard ActiveStorage processing" do
      variant = @user.avatar.variant(:thumb)
      expect(variant.pending?).to be true

      allow_any_instance_of(ActiveStorage::Variation).to receive(:transform) do |_variation, input, &block|
        block.call(input)
      end

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb)

      expect(variant.processed?).to be true
    end
  end

  describe "inline transformer" do
    it "processes the variant via background job" do
      variant = @user.avatar.variant(:thumb_inline)
      expect(variant.pending?).to be true

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_inline)

      expect(variant.processed?).to be true
      expect(variant.url).to be_present
      expect(variant.url).to end_with("/copy.png")
    end
  end

  describe "external transformer" do
    it "calls initiate with presigned URLs and callback URL" do
      FakeExternalTransformer.last_call = nil

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)

      expect(FakeExternalTransformer.last_call).to be_present
      expect(FakeExternalTransformer.last_call[:source_url]).to be_present
      expect(FakeExternalTransformer.last_call[:callback_url]).to be_present
    end

    it "sets variant to processing state after initiating" do
      variant = @user.avatar.variant(:thumb_external)

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)

      expect(variant.processing?).to be true
    end

    it "seeds the heartbeat and arms the watchdog" do
      variant = @user.avatar.variant(:thumb_external)

      expect {
        ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::HeartbeatWatchdogJob)

      record = variant.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record.last_heartbeat_at).to be_present
    end
  end

  describe "duplicate dispatch" do
    before do
      @initiated = 0
      allow_any_instance_of(FakeExternalTransformer).to receive(:initiate) { @initiated += 1 }
    end

    def thumb_record
      @user.avatar.blob.variant_records.find_by!(variation_digest: @user.avatar.variant(:thumb_external).variation.digest)
    end

    it "dispatches once while the first run is still heartbeating" do
      2.times { ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external) }

      expect(@initiated).to eq(1)
    end

    it "leaves a processed variant alone" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)
      thumb_record.update!(state: "processed")

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)

      expect(@initiated).to eq(1)
      expect(thumb_record.state).to eq("processed")
    end

    it "re-dispatches a run whose heartbeat went stale" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)
      thumb_record.update_columns(last_heartbeat_at: 2.minutes.ago)

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)

      expect(@initiated).to eq(2)
    end

    it "re-dispatches a failed variant" do
      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)
      thumb_record.update!(state: "failed")

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_external)

      expect(@initiated).to eq(2)
    end

    it "dispatches nothing when a processed blob is attached to another record" do
      @user.video.attach(io: File.open("spec/support/fixtures/image.png"), filename: "clip.mp4", content_type: "video/mp4", identify: false)
      perform_enqueued_jobs(only: ActiveStorage::AsyncVariants::ProcessJob)
      ActiveStorage::VariantRecord.update_all(state: "processed")

      User.create!.video.attach(@user.video.blob)
      perform_enqueued_jobs(only: ActiveStorage::AsyncVariants::ProcessJob)

      expect(@initiated).to eq(1)
    end

    it "dispatches a preview once while the first run is still heartbeating" do
      @user.video.attach(io: File.open("spec/support/fixtures/image.png"), filename: "clip.mp4", content_type: "video/mp4", identify: false)
      clear_enqueued_jobs

      2.times { ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :video, :poster_web) }

      expect(@initiated).to eq(1)
    end
  end

  describe "base Transformer" do
    it "raises NotImplementedError for process" do
      expect {
        ActiveStorage::AsyncVariants::Transformer.new.process(nil)
      }.to raise_error(NotImplementedError, /process/)
    end

    it "raises NotImplementedError for initiate" do
      expect {
        ActiveStorage::AsyncVariants::Transformer.new.initiate(source_url: "x", callback_url: "y")
      }.to raise_error(NotImplementedError, /initiate/)
    end

  end

  describe "failure handling" do
    it "marks variant as failed and enqueues retry on first failure" do
      variant = @user.avatar.variant(:thumb_failing)

      expect {
        ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_failing)
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)

      record = @user.avatar.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record.attempts).to eq(1)
      expect(record.state).to eq("failed")
      expect(record.error).to eq("ffmpeg exited with status 1")
    end

    it "permanently fails after exhausting retries" do
      variant = @user.avatar.variant(:thumb_failing)

      perform_enqueued_jobs do
        ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_failing)
      end

      record = @user.avatar.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record.attempts).to eq(3)
      expect(record.state).to eq("failed")
    end
  end
end
