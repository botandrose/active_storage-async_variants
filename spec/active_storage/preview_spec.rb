# frozen_string_literal: true

RSpec.describe "async variants: previews" do
  include_context "with an attached avatar"

  describe "async preview" do
    let(:blob) { @user.avatar.blob }
    # :thumb_preview is declared on User#avatar as
    #   resize_to_limit: [101, 101], transformer: FakePreviewTransformer, async: true
    # The Preview-side variation needs the same transformations so the
    # named-variant lookup in PreviewExtension#enqueue! can match it.
    let(:named_variant) { @user.avatar.variant(:thumb_preview) }
    let(:variation) { named_variant.variation }
    let(:preview) { ActiveStorage::Preview.new(blob, variation) }

    it "enqueues a ProcessJob via the matching named variant" do
      expect {
        preview.enqueue!
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end

    it "is idempotent when a variant_record already exists" do
      create_variant_record(named_variant, state: "pending")

      expect {
        preview.enqueue!
      }.not_to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end

    it "reports processed? from the variant_record on the original blob" do
      expect(preview.processed?).to be false
      simulate_processed_variant(named_variant)
      expect(preview.processed?).to be true
    end

    it "serves the variant URL when processed" do
      simulate_processed_variant(named_variant)

      expect(preview.url).to be_present
      expect(preview.url).to end_with("/thumb.png")
    end

    it "serves the original blob URL when not yet processed" do
      expect(preview.url).to end_with("/image.png")
    end

    it "serves the original when the variant has failed" do
      create_variant_record(named_variant, state: "failed", error: "boom")
      expect(preview.url).to end_with("/image.png")
    end

    it "returns variant blob key when processed" do
      simulate_processed_variant(named_variant)

      expect(preview.key).to be_present
    end

    it "raises UnprocessedError for key when not processed" do
      expect { preview.key }.to raise_error(ActiveStorage::Preview::UnprocessedError)
    end
  end

  describe "non-async preview passthrough" do
    let(:blob) { @user.avatar.blob }
    let(:variation) { ActiveStorage::Variation.wrap(resize_to_limit: [100, 100]) }
    let(:preview) { ActiveStorage::Preview.new(blob, variation) }

    it "delegates processed to standard ActiveStorage" do
      expect { preview.processed }.to raise_error(NoMethodError)
    end

    it "delegates url to standard ActiveStorage" do
      expect { preview.url }.to raise_error(ActiveStorage::Preview::UnprocessedError)
    end

    it "delegates key to standard ActiveStorage" do
      expect { preview.key }.to raise_error(ActiveStorage::Preview::UnprocessedError)
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
        async: true,
      )
      preview = ActiveStorage::Preview.new(blob, variation)

      expect(preview.async_state).to eq("pending")
    end

    it "returns the variant_record's state once processing has happened" do
      named_variant = @user.avatar.variant(:thumb_preview)
      simulate_processed_variant(named_variant)

      variation = named_variant.variation
      preview = ActiveStorage::Preview.new(blob, variation)

      expect(preview.async_state).to eq("processed")
    end
  end

  describe "Preview with URL-reconstructed variation (controller path)" do
    # When the RedirectController resolves a representation from the URL, it
    # rebuilds a Variation from the URL's variation_key. That key only carries
    # transformations -- :async / :transformer are stripped at
    # Variation#initialize and not embedded in the URL. The gem must recover
    # async_options by matching the rebuilt variation against the blob's
    # attached named variants.
    let(:blob) { @user.avatar.blob }
    let(:source_variant) { @user.avatar.variant(:thumb_preview) }
    let(:url_variation) { ActiveStorage::Variation.wrap(source_variant.variation.transformations) }
    let(:preview) { ActiveStorage::Preview.new(blob, url_variation) }

    it "starts with no async_options on the rebuilt variation" do
      expect(url_variation.async_options).to eq({})
    end

    it "resolves async_state via lookup against the parent attachment's named variants" do
      expect(preview.async_state).to eq("pending")
    end

    it "serves the original blob URL while pending" do
      expect(preview.url).to end_with("/image.png")
    end

    it "does not leak the preview_image blob URL when preview_image is attached" do
      blob.preview_image.attach(
        io: File.open("spec/support/fixtures/image.png"),
        filename: "preview.png",
        content_type: "image/png",
        service_name: blob.service.name,
      )

      expect(preview.url).to end_with("/image.png")
      expect(preview.url).not_to include(blob.preview_image.blob.key)
    end

    it "resolves async_options via attachment scan when the Registry is cold" do
      source_variant
      ActiveStorage::AsyncVariants::Registry.clear

      expect(preview.url).to end_with("/image.png")
    end
  end
end
