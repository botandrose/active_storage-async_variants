# frozen_string_literal: true

RSpec.describe "async variants: state endpoint and asset serving" do
  include_context "with an attached avatar"

  describe "touching attached records when variant reaches a terminal state" do
    it "touches the attachment's record when state transitions to processed" do
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")

      expect { variant_record.update!(state: "processed") }
        .to change { @user.reload.updated_at }
    end

    it "touches the attachment's record when state transitions to failed" do
      # Failed is also terminal: cached fragments that include data-async-
      # variant-state-value="pending" need to be invalidated so the next
      # render sees the new state.
      variant = @user.avatar.variant(:thumb)
      variant_record = create_variant_record(variant, state: "processing")

      expect { variant_record.update!(state: "failed", error: "boom") }
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

  describe "StatesController" do
    let(:client) { ActionDispatch::Integration::Session.new(Rails.application) }

    def state_path(variant, kind: "image", direct: "0")
      Rails.application.routes.url_helpers.async_variant_state_path(
        signed_blob_id: variant.blob.signed_id,
        variation_key: variant.variation.key,
        kind: kind,
        direct: direct,
        host: "example.com",
      )
    end

    it "renders the processing partial when state is pending" do
      variant = @user.avatar.variant(:thumb_proc)

      client.get state_path(variant)

      expect(client.response.status).to eq(200)
      expect(client.response.body).to include("turbo-frame")
      expect(client.response.body).to include("async-variant-processing")
      # Inline self-poll: Turbo activates <script>s in frame swaps, so each
      # pending/processing response schedules its own next reload.
      expect(client.response.body).to match(/setTimeout.*reload.*5000/)
    end

    it "renders the processing partial when state is processing" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "processing")

      client.get state_path(variant)

      expect(client.response.body).to include("async-variant-processing")
      expect(client.response.body).to match(/setTimeout.*reload.*5000/)
    end

    it "renders an indeterminate progress-bar when no progress is reported" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "processing")

      client.get state_path(variant)

      expect(client.response.body).to include("<progress-bar")
      expect(client.response.body).not_to match(/<progress-bar[^>]*percent=/)
    end

    it "renders a determinate progress-bar with the reported percent" do
      variant = @user.avatar.variant(:thumb_proc)
      record = create_variant_record(variant, state: "processing")
      record.update!(progress: 42)

      client.get state_path(variant)

      expect(client.response.body).to match(/<progress-bar[^>]*percent="42"/)
    end

    it "renders the failed partial when state is failed" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "failed", error: "boom")

      client.get state_path(variant)

      expect(client.response.body).to include("async-variant-failed")
      # Terminal state: no inline self-poll, so the chain stops.
      expect(client.response.body).not_to match(/setTimeout.*reload/)
    end

    # The hidden placeholder matches the eventual element so it reserves the
    # right box -- a zero-network <video> for video variants, an <img>
    # otherwise -- with the progress bar floating over it.
    it "renders a <video> placeholder for a video variant, not an <img>" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "processing")

      client.get state_path(variant, kind: "video")

      expect(client.response.body).to include("<video")
      expect(client.response.body).not_to include("<img")
    end

    it "renders a <video> placeholder for a failed video variant, not an <img>" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "failed", error: "boom")

      client.get state_path(variant, kind: "video")

      expect(client.response.body).to include("<video")
      expect(client.response.body).not_to include("<img")
    end

    it "renders the processed partial as an <img> when state is processed" do
      variant = @user.avatar.variant(:thumb_proc)
      simulate_processed_variant(variant)

      client.get state_path(variant)

      expect(client.response.body).to include("<img")
      expect(client.response.body).not_to match(/setTimeout.*reload/)
    end

    it "renders the processed partial as a <video> when kind=video" do
      variant = @user.avatar.variant(:thumb_proc)
      simulate_processed_variant(variant)

      client.get state_path(variant, kind: "video")

      expect(client.response.body).to include("<video")
    end

    it "404s for an invalid signed_blob_id" do
      variant = @user.avatar.variant(:thumb_proc)
      url = state_path(variant).sub(variant.blob.signed_id, "garbage")

      client.get url

      expect(client.response.status).to eq(404)
    end
  end

  describe "retry" do
    let(:client) { ActionDispatch::Integration::Session.new(Rails.application) }

    around do |example|
      previous = ActiveStorage::AsyncVariants.retry_visible_proc
      example.run
      ActiveStorage::AsyncVariants.retry_visible_proc = previous
    end

    def state_path(variant, kind: "image", direct: "0")
      Rails.application.routes.url_helpers.async_variant_state_path(
        signed_blob_id: variant.blob.signed_id,
        variation_key: variant.variation.key,
        kind: kind, direct: direct, host: "example.com",
      )
    end

    def retry_path(variant, kind: "image", direct: "0")
      Rails.application.routes.url_helpers.async_variant_state_retry_path(
        signed_blob_id: variant.blob.signed_id,
        variation_key: variant.variation.key,
        kind: kind, direct: direct, host: "example.com",
      )
    end

    it "renders the retry dialog, linking the served CSS/JS, when retry is visible" do
      ActiveStorage::AsyncVariants.retry_visible_if { true }
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "failed", error: "boom")

      client.get state_path(variant)
      body = client.response.body

      expect(body).to include("async-variant-retry")
      expect(body).to include("Retry processing")
      expect(body).to include("boom")
      expect(body).to match(%r{/active_storage/async_variants/assets/retry\.css})
      expect(body).to match(%r{/active_storage/async_variants/assets/retry\.js})
      # The bulk CSS/JS is referenced, not inlined.
      expect(body).not_to include(".opener {")
      expect(body).not_to include("customElements.define")
    end

    it "omits the retry dialog when the visibility block raises" do
      ActiveStorage::AsyncVariants.retry_visible_if { raise "boom" }
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "failed", error: "x")

      client.get state_path(variant)

      expect(client.response.body).to include("async-variant-failed")
      expect(client.response.body).not_to include("async-variant-retry")
    end

    it "destroys the failed record, re-enqueues processing, and redirects" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "failed", error: "boom")

      expect {
        client.post retry_path(variant)
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)

      expect(client.response.status).to eq(303)
      expect(client.response.headers["Location"]).to match(%r{/active_storage/async_variants/states/})

      record = variant.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      expect(record.state).to eq("pending")
    end
  end

  describe "engine asset serving" do
    let(:client) { ActionDispatch::Integration::Session.new(Rails.application) }

    def engine_asset_path(file)
      Rails.application.routes.url_helpers.async_variant_asset_path(file, host: "example.com")
    end

    it "serves retry.css with long-lived public cache headers" do
      client.get engine_asset_path("retry.css")

      expect(client.response.status).to eq(200)
      expect(client.response.content_type).to include("text/css")
      expect(client.response.headers["Cache-Control"]).to include("public")
      expect(client.response.headers["Cache-Control"]).to match(/max-age=\d+/)
      expect(client.response.body).to include("--retry-opener-display")
    end

    it "serves retry.js" do
      client.get engine_asset_path("retry.js")

      expect(client.response.status).to eq(200)
      expect(client.response.content_type).to include("javascript")
      expect(client.response.body).to include("customElements.define")
    end

    it "404s for an unknown asset" do
      client.get engine_asset_path("nope.css")

      expect(client.response.status).to eq(404)
    end
  end
end
