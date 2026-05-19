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

  describe "processing: :original" do
    it "serves the original URL when variant is not yet processed" do
      variant = @user.avatar.variant(:thumb)
      expect(variant.url).to be_present
      expect(variant.url).to end_with("/image.png")
    end
  end

  describe "non-async variant" do
    it "serves the original blob URL on cloud when variant is not yet processed" do
      variant = @user.avatar.variant(:thumb_sync)
      expect(variant.url).to end_with("/image.png")
    end
  end

  describe "processing: :blank" do
    it "returns nil when variant is not yet processed" do
      variant = @user.avatar.variant(:thumb_blank)
      expect(variant.url).to be_nil
    end
  end

  describe "processing: Proc" do
    it "calls the proc when variant is not yet processed" do
      variant = @user.avatar.variant(:thumb_custom)
      expect(variant.url).to eq("/placeholders/processing.svg")
    end
  end

  describe "failed:" do
    it "serves the processing placeholder while pending" do
      variant = @user.avatar.variant(:thumb_with_error_image)
      expect(variant.url).to end_with("/image.png")
    end

    it "serves the failed: string URL when the variant is failed" do
      variant = @user.avatar.variant(:thumb_with_error_image)
      create_variant_record(variant, state: "failed", error: "boom")

      expect(variant.url).to eq("/icons/broken.svg")
    end

    it "calls a Proc failed: with the blob when failed" do
      variant = @user.avatar.variant(:thumb_with_error_proc)
      create_variant_record(variant, state: "failed", error: "boom")

      expect(variant.url).to eq("/errors/image.png.svg")
    end

    it "returns nil for failed: :blank when failed" do
      variant = @user.avatar.variant(:thumb_with_error_blank)
      create_variant_record(variant, state: "failed", error: "boom")

      expect(variant.url).to be_nil
    end

    it "falls back to the processing placeholder when failed: is not specified" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "failed", error: "boom")

      expect(variant.url).to end_with("/image.png")
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

  describe "touching attached records when variant becomes processed" do
    it "touches the attachment's record when state transitions to processed" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")

      expect { variant_record.update!(state: "processed") }
        .to change { @user.reload.updated_at }
    end

    it "does not touch records on intermediate state transitions" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "pending")

      expect { variant_record.update!(state: "processing") }
        .not_to change { @user.reload.updated_at }
    end

    it "does not touch records when state is unchanged" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processed")

      expect { variant_record.update!(error: "no-op") }
        .not_to change { @user.reload.updated_at }
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
    it "enqueues a ProcessJob when variant is pending" do
      variant = @user.avatar.variant(:thumb_inline)

      expect {
        variant.processed
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)

      expect(variant.pending?).to be true
    end

    it "does not enqueue a ProcessJob when variant is already processing" do
      variant = @user.avatar.variant(:thumb_inline)
      create_variant_record(variant, state: "processing")

      expect {
        variant.processed
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end

    it "does not enqueue a ProcessJob when variant is already processed" do
      variant = @user.avatar.variant(:thumb_inline)
      simulate_processed_variant(variant)

      expect {
        variant.processed
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end

    it "only enqueues one ProcessJob across repeated calls before the job runs" do
      variant = @user.avatar.variant(:thumb_inline)

      expect {
        4.times { variant.processed }
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob).exactly(:once)
    end

    it "creates a pending variant record on first call to dedupe further calls" do
      variant = @user.avatar.variant(:thumb_inline)
      variant.processed

      record = variant.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record).to be_present
      expect(record.state).to eq("pending")
    end

    it "does not re-enqueue once the record is in failed state — give up permanently" do
      variant = @user.avatar.variant(:thumb_inline)
      create_variant_record(variant, state: "failed", error: "boom")

      expect {
        variant.processed
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end

    it "skips synchronous processing on cloud for non-async variants" do
      variant = @user.avatar.variant(:thumb_sync)
      variant.processed

      record = @user.avatar.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record).to be_nil
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

  describe "URL-decoded variants" do
    it "serves fallback by looking up named variant definition" do
      named_variant = @user.avatar.variant(:thumb)
      decoded_variation = ActiveStorage::Variation.decode(named_variant.variation.key)
      url_decoded_variant = ActiveStorage::VariantWithRecord.new(@user.avatar.blob, decoded_variation)

      expect(url_decoded_variant.variation.async_options).to eq({})
      expect(url_decoded_variant.url).to end_with("/image.png")
    end

    it "serves the variant URL when ready" do
      named_variant = @user.avatar.variant(:thumb)
      simulate_processed_variant(named_variant)

      decoded_variation = ActiveStorage::Variation.decode(named_variant.variation.key)
      url_decoded_variant = ActiveStorage::VariantWithRecord.new(@user.avatar.blob, decoded_variation)

      expect(url_decoded_variant.url).to end_with("/thumb.png")
    end

    it "enqueues processing from processed" do
      named_variant = @user.avatar.variant(:thumb)
      decoded_variation = ActiveStorage::Variation.decode(named_variant.variation.key)
      url_decoded_variant = ActiveStorage::VariantWithRecord.new(@user.avatar.blob, decoded_variation)

      expect {
        result = url_decoded_variant.processed
        expect(result).to eq(url_decoded_variant)
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end

    it "falls back to blob URL when no attachment exists (direct upload)" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open("spec/support/fixtures/image.png"),
        filename: "direct.png",
        content_type: "image/png",
      )
      variation = ActiveStorage::Variation.wrap(resize_to_limit: [100, 100])
      variant = ActiveStorage::VariantWithRecord.new(blob, variation)

      expect(variant.url).to end_with("/direct.png")
    end
  end

  describe "async preview" do
    let(:blob) { @user.avatar.blob }

    let(:preview) do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        processing: :original,
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

    it "returns nil for processing: :blank" do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        processing: :blank,
      )
      blank_preview = ActiveStorage::Preview.new(blob, variation)

      expect(blank_preview.url).to be_nil
    end

    it "calls proc for processing: Proc" do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        processing: ->(_blob) { "/placeholders/video.svg" },
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

  describe "#async_state on VariantWithRecord" do
    it "returns nil when the service does not respond to :bucket" do
      variant = @user.avatar.variant(:thumb)
      allow(variant.blob.service).to receive(:respond_to?).and_call_original
      allow(variant.blob.service).to receive(:respond_to?).with(:bucket).and_return(false)

      expect(variant.async_state).to be_nil
    end

    it "returns 'pending' when no variant record exists yet" do
      variant = @user.avatar.variant(:thumb)

      expect(variant.async_state).to eq("pending")
    end

    it "returns the underlying record's state when one exists" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "processing")

      expect(variant.async_state).to eq("processing")
    end
  end

  describe "#async_state on Preview" do
    let(:blob) { @user.avatar.blob }

    it "returns nil for non-async previews" do
      variation = ActiveStorage::Variation.wrap(resize_to_limit: [100, 100])
      preview = ActiveStorage::Preview.new(blob, variation)

      expect(preview.async_state).to be_nil
    end

    it "returns 'pending' for an async preview that has not been processed" do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        processing: :original,
      )
      preview = ActiveStorage::Preview.new(blob, variation)

      expect(preview.async_state).to eq("pending")
    end

    it "returns the preview variant record's state once processing has happened" do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        processing: :original,
      )
      preview = ActiveStorage::Preview.new(blob, variation)
      preview.process

      expect(preview.async_state).to eq("processed")
    end
  end

  describe "RedirectController extension" do
    def representation_url(variant)
      Rails.application.routes.url_helpers.rails_blob_representation_url(
        signed_blob_id: variant.blob.signed_id,
        variation_key: variant.variation.key,
        filename: variant.blob.filename,
        host: "example.com",
      )
    end

    let(:client) { ActionDispatch::Integration::Session.new(Rails.application) }

    it "serves the configured public-path fallback inline with the async state header when pending" do
      variant = @user.avatar.variant(:thumb_proc)

      client.get representation_url(variant)

      expect(client.response.status).to eq(200)
      expect(client.response.headers["X-Async-Variant-State"]).to eq("pending")
      expect(client.response.headers["Cache-Control"]).to include("no-store").and include("private")
      expect(client.response.body).to include("<svg")
    end

    it "exposes the processing state on the header while the job is running" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "processing")

      client.get representation_url(variant)

      expect(client.response.status).to eq(200)
      expect(client.response.headers["X-Async-Variant-State"]).to eq("processing")
    end

    it "serves the failed: fallback inline with state=failed when the variant has failed" do
      variant = @user.avatar.variant(:thumb_with_error_image)
      create_variant_record(variant, state: "failed", error: "boom")

      client.get representation_url(variant)

      expect(client.response.status).to eq(200)
      expect(client.response.headers["X-Async-Variant-State"]).to eq("failed")
      expect(client.response.body).to include("<svg")
    end

    it "falls through to the standard redirect for processed variants" do
      variant = @user.avatar.variant(:thumb_proc)
      simulate_processed_variant(variant)

      client.get representation_url(variant)

      expect(client.response.status).to eq(302)
      expect(client.response.headers["X-Async-Variant-State"]).to be_nil
    end

    it "falls through when the fallback resolves to a path that is not a public file" do
      variant = @user.avatar.variant(:thumb)

      client.get representation_url(variant)

      expect(client.response.status).to eq(302)
      expect(client.response.headers["X-Async-Variant-State"]).to be_nil
    end
  end
end
