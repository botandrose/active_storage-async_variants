# frozen_string_literal: true

RSpec.describe "async variants: previews" do
  include_context "with an attached avatar"

  describe "async preview" do
    before { attach_video_to(@user) }

    # :poster is declared on User#video as
    #   resize_to_limit: [300, 300], format: :jpg, transformer: FakeExternalTransformer, async: true
    let(:preview) { @user.video.preview(:poster) }

    it "reports processed? from the variant_record on the frame blob" do
      expect(preview.processed?).to be false
      simulate_processed_preview(preview)
      expect(preview.processed?).to be true
    end

    it "serves the variant URL when processed" do
      simulate_processed_preview(preview)

      expect(preview.url).to be_present
      expect(preview.url).to end_with("/poster.jpg")
    end

    it "serves the original blob URL when not yet processed" do
      expect(preview.url).to end_with("/movie.mp4")
    end

    it "serves the original when the variant has failed" do
      ActiveStorage::AsyncVariants.ensure_preview_image_placeholder!(@user.video.blob)
      create_variant_record(preview.send(:variant), state: "failed", error: "boom")

      expect(preview.url).to end_with("/movie.mp4")
    end

    it "returns variant blob key when processed" do
      simulate_processed_preview(preview)

      expect(preview.key).to be_present
    end

    it "raises UnprocessedError for key when not processed" do
      expect { preview.key }.to raise_error(ActiveStorage::Preview::UnprocessedError)
    end
  end

  describe "non-async preview passthrough" do
    let(:blob) { @user.avatar.blob }
    let(:variation) { ActiveStorage::Variation.wrap(resize_to_limit: [99, 99]) }
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
      variation = ActiveStorage::Variation.wrap(resize_to_limit: [99, 99])
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
      attach_video_to(@user)
      simulate_processed_preview(@user.video.preview(:poster))

      expect(@user.video.preview(:poster).async_state).to eq("processed")
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
