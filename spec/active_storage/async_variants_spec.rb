# frozen_string_literal: true

RSpec.describe "async variants" do
  before do
    @user = User.create!
    @user.avatar.attach(
      io: File.open("spec/support/fixtures/image.png"),
      filename: "image.png",
      content_type: "image/png",
    )
  end

  describe "fallback: :original" do
    it "serves the original URL when variant is not yet processed" do
      variant = @user.avatar.variant(:thumb)
      expect(variant.url).to be_present
      expect(variant.url).to end_with("/image.png")
    end
  end

  describe "without fallback" do
    it "returns nil when variant is not yet processed (standard behavior)" do
      variant = @user.avatar.variant(:thumb_sync)
      expect(variant.url).to be_nil
    end
  end

  describe "fallback: :blank" do
    it "returns nil when variant is not yet processed" do
      variant = @user.avatar.variant(:thumb_blank)
      expect(variant.url).to be_nil
    end
  end

  describe "fallback: Proc" do
    it "calls the proc when variant is not yet processed" do
      variant = @user.avatar.variant(:thumb_custom)
      expect(variant.url).to eq("/placeholders/processing.svg")
    end
  end

  describe "after processing" do
    it "serves the variant URL, not the fallback" do
      variant = @user.avatar.variant(:thumb)
      simulate_processed_variant(variant)

      expect(variant.url).to be_present
      expect(variant.url).to end_with("/thumb.png")
    end

    it "still serves fallback when variant record exists but is not processed" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "processing")

      expect(variant.url).to end_with("/image.png")
    end
  end

  describe "state query API" do
    it "reports pending when no record exists" do
      variant = @user.avatar.variant(:thumb)
      expect(variant.pending?).to be true
      expect(variant.processing?).to be false
      expect(variant.ready?).to be false
      expect(variant.failed?).to be false
      expect(variant.error).to be_nil
    end

    it "reports processing when record state is processing" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "processing")

      expect(variant.pending?).to be false
      expect(variant.processing?).to be true
      expect(variant.ready?).to be false
      expect(variant.failed?).to be false
    end

    it "reports ready when variant is processed" do
      variant = @user.avatar.variant(:thumb)
      simulate_processed_variant(variant)

      expect(variant.pending?).to be false
      expect(variant.processing?).to be false
      expect(variant.ready?).to be true
      expect(variant.failed?).to be false
    end

    it "reports failed with error message" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "failed", error: "ffmpeg exited with status 1")

      expect(variant.pending?).to be false
      expect(variant.processing?).to be false
      expect(variant.ready?).to be false
      expect(variant.failed?).to be true
      expect(variant.error).to eq("ffmpeg exited with status 1")
    end
  end

  describe "callback endpoint", type: :request do
    it "transitions variant to processed on success callback" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "success", content_type: "image/webp", byte_size: 1234 },
        as: :json

      expect(response).to have_http_status(:ok)
      variant_record.reload
      expect(variant_record.state).to eq("processed")
    end

    it "transitions variant to failed on failure callback" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "failed", error: "ffmpeg exited with status 1" },
        as: :json

      expect(response).to have_http_status(:ok)
      variant_record.reload
      expect(variant_record.state).to eq("failed")
      expect(variant_record.error).to eq("ffmpeg exited with status 1")
    end

    it "rejects requests with invalid tokens" do
      post "/active_storage/async_variants/callbacks/invalid-token",
        params: { status: "success" },
        as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "default transformer (no transformer: option)" do
    it "processes the variant using standard ActiveStorage processing" do
      variant = @user.avatar.variant(:thumb)
      expect(variant.pending?).to be true

      allow_any_instance_of(ActiveStorage::Variation).to receive(:transform) do |_variation, input, &block|
        block.call(input)
      end

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb)

      expect(variant.ready?).to be true
    end
  end

  describe "inline transformer" do
    it "processes the variant via background job" do
      variant = @user.avatar.variant(:thumb_inline)
      expect(variant.pending?).to be true

      ActiveStorage::AsyncVariants::ProcessJob.perform_now(@user, :avatar, :thumb_inline)

      expect(variant.ready?).to be true
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
  end

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

    it "does not enqueue jobs for variants without fallback" do
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
    it "does not trigger processing for async variants" do
      variant = @user.avatar.variant(:thumb_inline)

      variant.processed

      expect(variant.pending?).to be true
    end

    it "delegates to standard ActiveStorage for non-async variants" do
      variant = @user.avatar.variant(:thumb_sync)

      allow_any_instance_of(ActiveStorage::Variation).to receive(:transform) do |_variation, input, &block|
        block.call(input)
      end

      variant.processed

      record = @user.avatar.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record).to be_present
      expect(record.image).to be_attached
    end
  end

  describe "async preview" do
    let(:blob) { @user.avatar.blob }

    let(:preview) do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        fallback: :original,
      )
      ActiveStorage::Preview.new(blob, variation)
    end

    before { FakePreviewTransformer.process_preview_called = false }

    it "does not trigger processing via processed" do
      preview.processed

      expect(FakePreviewTransformer.process_preview_called).to be false
    end

    it "delegates to transformer.process_preview via process" do
      preview.process

      expect(FakePreviewTransformer.process_preview_called).to be true
    end

    it "reports processed after transformer completes" do
      preview.process

      expect(preview.processed?).to be true
    end

    it "serves the variant URL when processed" do
      preview.process

      expect(preview.url).to be_present
      expect(preview.url).to end_with("/thumb.png")
    end

    it "serves fallback URL when not yet processed" do
      expect(preview.url).to end_with("/image.png")
    end

    it "returns nil for fallback: :blank" do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        fallback: :blank,
      )
      blank_preview = ActiveStorage::Preview.new(blob, variation)

      expect(blank_preview.url).to be_nil
    end

    it "calls proc for fallback: Proc" do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        fallback: ->(_blob) { "/placeholders/video.svg" },
      )
      custom_preview = ActiveStorage::Preview.new(blob, variation)

      expect(custom_preview.url).to eq("/placeholders/video.svg")
    end

    it "does not call process_preview if preview_image already attached" do
      preview.process
      FakePreviewTransformer.process_preview_called = false

      preview.process

      expect(FakePreviewTransformer.process_preview_called).to be false
    end

    it "returns variant blob key when processed" do
      preview.process

      expect(preview.key).to be_present
    end

    it "raises UnprocessedError for key when not processed" do
      expect { preview.key }.to raise_error(ActiveStorage::Preview::UnprocessedError)
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

    it "raises NotImplementedError for process_preview" do
      expect {
        ActiveStorage::AsyncVariants::Transformer.new.process_preview(blob: nil, variation: nil)
      }.to raise_error(NotImplementedError, /process_preview/)
    end
  end

  describe "Variation with non-Hash input" do
    it "defaults async_options to empty hash" do
      transformations = Struct.new(:deep_symbolize_keys).new({})
      variation = ActiveStorage::Variation.new(transformations)
      expect(variation.async_options).to eq({})
    end
  end


  describe "non-async preview passthrough" do
    let(:blob) { @user.avatar.blob }
    let(:variation) { ActiveStorage::Variation.wrap(resize_to_limit: [100, 100]) }
    let(:preview) { ActiveStorage::Preview.new(blob, variation) }

    it "delegates process to standard ActiveStorage" do
      expect { preview.process }.to raise_error(NoMethodError)
    end

    it "delegates url to standard ActiveStorage" do
      expect { preview.url }.to raise_error(ActiveStorage::Preview::UnprocessedError)
    end

    it "delegates key to standard ActiveStorage" do
      expect { preview.key }.to raise_error(ActiveStorage::Preview::UnprocessedError)
    end
  end

  describe "callback with unknown status", type: :request do
    it "returns unprocessable_entity" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")
      token = ActiveStorage::AsyncVariants.callback_token_for(variant_record)

      post "/active_storage/async_variants/callbacks/#{token}",
        params: { status: "unknown" },
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
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
