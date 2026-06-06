# frozen_string_literal: true

RSpec.describe "async variants: previews" do
  include_context "with an attached avatar"

  describe "async preview" do
    let(:blob) { @user.avatar.blob }
    # :thumb_preview is declared on User#avatar as
    #   resize_to_limit: [101, 101], format: "png",
    #   transformer: FakePreviewTransformer, processing: "/spinner.svg"
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

    it "serves the configured String fallback when not yet processed" do
      expect(preview.url).to eq("/spinner.svg")
    end

    it "serves the failed: fallback URL when the variant has failed" do
      named_variant = @user.avatar.variant(:thumb_preview_with_failed)
      variation = named_variant.variation
      create_variant_record(named_variant, state: "failed", error: "boom")
      preview = ActiveStorage::Preview.new(blob, variation)

      expect(preview.url).to eq("/icons/broken.svg")
    end

    it "falls back to processing: when failed: is not configured" do
      # :thumb_preview (used above) has no failed: -- failed state should
      # still serve the processing fallback rather than nil.
      create_variant_record(named_variant, state: "failed", error: "boom")
      expect(preview.url).to eq("/spinner.svg")
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

  describe "async preview with processing: :original" do
    let(:blob) { @user.avatar.blob }

    it "returns the original blob URL while pending" do
      variation = ActiveStorage::Variation.wrap(
        resize_to_limit: [100, 100],
        transformer: FakePreviewTransformer,
        processing: :original,
      )
      preview = ActiveStorage::Preview.new(blob, variation)

      expect(preview.url).to end_with("/image.png")
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
    # transformations -- :transformer, :processing, :failed are stripped at
    # Variation#initialize and not embedded in the URL. The gem must recover
    # async_options by matching the rebuilt variation against the blob's
    # attached named variants.
    let(:blob) { @user.avatar.blob }
    # Mirror what RedirectController does: take the encoded transformations
    # from the source variant, then rebuild a Variation from them. The result
    # has the same `transformations` (including default :format) but its
    # `async_options` is empty -- :transformer / :processing are stripped at
    # Variation#initialize and aren't in the URL key.
    let(:source_variant) { @user.avatar.variant(:thumb_preview) }
    let(:url_variation) { ActiveStorage::Variation.wrap(source_variant.variation.transformations) }
    let(:preview) { ActiveStorage::Preview.new(blob, url_variation) }

    it "starts with no async_options on the rebuilt variation" do
      expect(url_variation.async_options).to eq({})
    end

    it "resolves async_state via lookup against the parent attachment's named variants" do
      expect(preview.async_state).to eq("pending")
    end

    it "serves the named variant's String processing fallback while pending" do
      expect(preview.url).to eq("/spinner.svg")
    end

    it "does not leak the preview_image blob URL when preview_image is attached" do
      blob.preview_image.attach(
        io: File.open("spec/support/fixtures/image.png"),
        filename: "preview.png",
        content_type: "image/png",
        service_name: blob.service.name,
      )

      expect(preview.url).to eq("/spinner.svg")
      expect(preview.url).not_to include(blob.preview_image.blob.key)
    end

    it "resolves async_options via attachment scan when the Registry is cold" do
      # Force the URL-reconstructed path to fall through to the
      # find_named_async_variant_options walk by emptying the digest cache.
      source_variant
      ActiveStorage::AsyncVariants::Registry.clear

      expect(preview.url).to eq("/spinner.svg")
    end
  end

  describe "Preview with String processing: fallback" do
    let(:blob) { @user.avatar.blob }

    it "returns the configured String when not yet processed" do
      variation = ActiveStorage::Variation.wrap(
        transformer: FakePreviewTransformer,
        processing: "/icons/loading.svg",
      )
      preview = ActiveStorage::Preview.new(blob, variation)

      expect(preview.url).to eq("/icons/loading.svg")
    end
  end
end
