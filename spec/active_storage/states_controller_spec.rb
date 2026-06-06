# frozen_string_literal: true

RSpec.describe "async variants: state endpoint" do
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
      expect(client.response.body).to match(/setTimeout.*reload.*3000/)
    end

    it "renders the processing partial when state is processing" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "processing")

      client.get state_path(variant)

      expect(client.response.body).to include("async-variant-processing")
      expect(client.response.body).to match(/setTimeout.*reload.*3000/)
    end

    it "renders the failed partial when state is failed" do
      variant = @user.avatar.variant(:thumb_proc)
      create_variant_record(variant, state: "failed", error: "boom")

      client.get state_path(variant)

      expect(client.response.body).to include("async-variant-failed")
      # Terminal state: no inline self-poll, so the chain stops.
      expect(client.response.body).not_to match(/setTimeout.*reload/)
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
end
