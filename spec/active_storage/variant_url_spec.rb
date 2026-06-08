# frozen_string_literal: true

RSpec.describe "async variants: variant URL resolution" do
  include_context "with an attached avatar"

  describe "unprocessed async variant" do
    it "serves the original URL when the variant is not yet processed" do
      variant = @user.avatar.variant(:thumb)
      expect(variant.url).to be_present
      expect(variant.url).to end_with("/image.png")
    end
  end

  describe "non-async variant" do
    # A named variant declared with no async options is a standard sync
    # variant. The gem must not intercept its URL with the source-blob URL --
    # that would mean a thumb_variant call resolves to the originally uploaded
    # blob. Defer to standard Rails behavior instead.
    it "defers to standard Rails (returns nil for an unprocessed variant) instead of leaking the source blob URL" do
      variant = @user.avatar.variant(:thumb_sync)
      expect(variant.url).to be_nil
    end
  end

  describe "VariantWithRecord with URL-reconstructed variation that matches no named variant" do
    # A variation rebuilt from the URL may not match any of the blob's named
    # variants. The gem must not fall back to the source blob URL in that case.
    it "defers to super instead of returning the source blob URL" do
      variation = ActiveStorage::Variation.wrap(resize_to_limit: [9999, 9999])
      variant = ActiveStorage::VariantWithRecord.new(@user.avatar.blob, variation)
      expect(variant.url).to be_nil
    end
  end

  describe "VariantWithRecord on a preview_image blob with a cold Registry" do
    # Simulates the production case: AS RepresentationsRedirectController
    # resolves a request like /rails/active_storage/representations/redirect/
    # <preview_blob>/<variation_key>/.... The preview blob has only a
    # preview_image attachment (which has no named_variants), so the gem must
    # walk one level back via preview_image -> source blob -> named variants
    # to recover the async config and serve the original.
    it "recovers the async config via the source blob's named variant and serves the original" do
      preview_blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open("spec/support/fixtures/image.png"),
        filename: "preview.png",
        content_type: "image/png",
        service_name: "test",
      )
      @user.avatar.blob.preview_image.attach(preview_blob)
      url_variation = ActiveStorage::Variation.wrap(
        @user.avatar.variant(:thumb_preview).variation.transformations
      )
      ActiveStorage::AsyncVariants::Registry.clear

      variant = ActiveStorage::VariantWithRecord.new(preview_blob, url_variation)

      expect(variant.url).to end_with("/preview.png")
    end

    it "keeps scanning when the source blob has no matching named variant" do
      preview_blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open("spec/support/fixtures/image.png"),
        filename: "preview.png",
        content_type: "image/png",
        service_name: "test",
      )
      @user.avatar.blob.preview_image.attach(preview_blob)
      url_variation = ActiveStorage::Variation.wrap(resize_to_limit: [999, 999])
      ActiveStorage::AsyncVariants::Registry.clear

      variant = ActiveStorage::VariantWithRecord.new(preview_blob, url_variation)

      expect(variant.send(:resolved_async_options)).to eq({})
    end
  end

  describe "while not processed" do
    it "serves the original when a failed record exists" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "failed", error: "boom")

      expect(variant.url).to end_with("/image.png")
    end

    it "serves the original when a processing record exists" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "processing")

      expect(variant.url).to end_with("/image.png")
    end
  end

  describe "after processing" do
    it "serves the variant URL, not the original" do
      variant = @user.avatar.variant(:thumb)
      simulate_processed_variant(variant)

      expect(variant.url).to be_present
      expect(variant.url).to end_with("/thumb.png")
    end
  end

  describe "state query API" do
    it "reports pending when no record exists" do
      variant = @user.avatar.variant(:thumb)
      expect(variant.pending?).to be true
      expect(variant.processing?).to be false
      expect(variant.processed?).to be false
      expect(variant.failed?).to be false
      expect(variant.error).to be_nil
    end

    it "reports processing when record state is processing" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "processing")

      expect(variant.pending?).to be false
      expect(variant.processing?).to be true
      expect(variant.processed?).to be false
      expect(variant.failed?).to be false
    end

    it "reports processed when variant is processed" do
      variant = @user.avatar.variant(:thumb)
      simulate_processed_variant(variant)

      expect(variant.pending?).to be false
      expect(variant.processing?).to be false
      expect(variant.processed?).to be true
      expect(variant.failed?).to be false
    end

    it "reports failed with error message" do
      variant = @user.avatar.variant(:thumb)
      create_variant_record(variant, state: "failed", error: "ffmpeg exited with status 1")

      expect(variant.pending?).to be false
      expect(variant.processing?).to be false
      expect(variant.processed?).to be false
      expect(variant.failed?).to be true
      expect(variant.error).to eq("ffmpeg exited with status 1")
    end
  end

  describe "URL-decoded variants" do
    it "serves the original by looking up the named variant definition" do
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

    it "enqueues via enqueue! using the matching named variant declaration" do
      named_variant = @user.avatar.variant(:thumb)
      decoded_variation = ActiveStorage::Variation.decode(named_variant.variation.key)
      url_decoded_variant = ActiveStorage::VariantWithRecord.new(@user.avatar.blob, decoded_variation)

      expect {
        url_decoded_variant.enqueue!
      }.to have_enqueued_job(ActiveStorage::AsyncVariants::ProcessJob)
    end

    it "defers to standard Rails when no attachment exists to look up async config" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open("spec/support/fixtures/image.png"),
        filename: "direct.png",
        content_type: "image/png",
      )
      variation = ActiveStorage::Variation.wrap(resize_to_limit: [100, 100])
      variant = ActiveStorage::VariantWithRecord.new(blob, variation)

      expect(variant.url).to be_nil
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
end
