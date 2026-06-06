# frozen_string_literal: true

RSpec.describe "async variants: enqueueing" do
  include_context "with an attached avatar"

  describe "auto-enqueue on attachment" do
    it "enqueues a ProcessJob for each async variant when a file is attached" do
      user = User.create!

      expect {
        user.avatar.attach(
          io: File.open("spec/support/fixtures/image.png"),
          filename: "image.png",
          content_type: "image/png",
        )
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob).at_least(:once)
    end

    it "does not enqueue jobs for non-async variants" do
      user = User.create!

      user.avatar.attach(
        io: File.open("spec/support/fixtures/image.png"),
        filename: "image.png",
        content_type: "image/png",
      )

      enqueued_variant_names = ActiveJob::Base.queue_adapter.enqueued_jobs
        .select { |job| job["job_class"] == "ActiveStorage::AsyncVariants::ProcessJob" }
        .map { |job| job["arguments"].last }

      expect(enqueued_variant_names).not_to include("thumb_sync")
    end
  end

  describe "variant.processed" do
    it "is a no-op on cloud storage (no synchronous transform, no enqueue)" do
      variant = @user.avatar.variant(:thumb_inline)

      expect {
        result = variant.processed
        expect(result).to eq(variant)
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)

      expect(variant.blob.variant_records).to be_empty
    end

    it "delegates to standard ActiveStorage on disk storage" do
      variant = @user.avatar.variant(:thumb_sync)
      allow(variant.blob.service).to receive(:respond_to?).and_call_original
      allow(variant.blob.service).to receive(:respond_to?).with(:bucket).and_return(false)

      allow_any_instance_of(ActiveStorage::Variation).to receive(:transform) do |_variation, input, &block|
        block.call(input)
      end

      variant.processed

      record = @user.avatar.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record).to be_present
      expect(record.image).to be_attached
    end
  end

  describe "variant.enqueue!" do
    it "enqueues a ProcessJob and creates a pending variant_record" do
      variant = @user.avatar.variant(:thumb_inline)

      expect {
        variant.enqueue!
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)

      record = variant.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record.state).to eq("pending")
    end

    it "is idempotent across repeated calls (RecordNotUnique guards dedupe)" do
      variant = @user.avatar.variant(:thumb_inline)

      expect {
        4.times { variant.enqueue! }
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob).exactly(:once)
    end

    it "does not re-enqueue when a variant_record already exists (any state)" do
      variant = @user.avatar.variant(:thumb_inline)
      create_variant_record(variant, state: "failed", error: "boom")

      expect {
        variant.enqueue!
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end

    it "is a no-op when no named variant matches the variation" do
      variation = ActiveStorage::Variation.wrap(resize_to_limit: [9999, 9999])
      variant = ActiveStorage::VariantWithRecord.new(@user.avatar.blob, variation)

      expect {
        variant.enqueue!
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end
  end
end
