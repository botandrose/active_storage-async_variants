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
