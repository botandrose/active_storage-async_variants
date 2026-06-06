# frozen_string_literal: true

RSpec.describe "async variants: view helpers" do
  include_context "with an attached avatar"

  describe "image_tag / video_tag async: and direct: options" do
    let(:helper) do
      view = ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([]), {}, nil)
      view.singleton_class.include(Rails.application.routes.url_helpers)
      view.define_singleton_method(:default_url_options) { { host: "example.com", protocol: "https" } }
      view
    end

    let(:variant) { @user.avatar.variant(:thumb_proc) }

    around do |example|
      previous = ActiveStorage::AsyncVariants.cdn_host
      ActiveStorage::AsyncVariants.cdn_host = nil
      example.run
      ActiveStorage::AsyncVariants.cdn_host = previous
    end

    it "passes through when neither async: nor direct: is given" do
      html = helper.image_tag(variant, alt: "x")
      expect(html).to include("src=")
      expect(html).not_to include("turbo-frame")
    end

    it "passes through string sources untouched" do
      html = helper.image_tag("https://example.com/foo.png", alt: "x")
      expect(html).to include("src=\"https://example.com/foo.png\"")
      expect(html).not_to include("turbo-frame")
    end

    it "raises ArgumentError when async: is given with a non-variant source" do
      expect { helper.image_tag("foo.png", async: true) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when direct: is given with a non-variant source" do
      expect { helper.image_tag("foo.png", direct: true) }.to raise_error(ArgumentError)
    end

    context "with async: true for a non-bucket-backed blob (Disk-only deployments)" do
      it "emits a plain <img> (vanilla AS handles sync processing on Disk)" do
        allow(variant.blob).to receive(:bucket_backed?).and_return(false)
        html = helper.image_tag(variant, async: true)
        expect(html).to include("<img")
        expect(html).not_to include("turbo-frame")
      end
    end

    context "with async: true for a bucket-backed blob and an unprocessed variant" do
      before do
        allow(variant.blob).to receive(:bucket_backed?).and_return(true)
      end

      it "emits a <turbo-frame> pointing at the state endpoint" do
        html = helper.image_tag(variant, async: true)
        expect(html).to include("<turbo-frame")
        expect(html).to include("/active_storage/async_variants/states/")
        expect(html).to match(/id="async-variant-\d+-[A-Za-z0-9_-]+"/)
      end

      it "passes alt/width/height through opts[] in the state URL" do
        html = helper.image_tag(variant, async: true, alt: "portrait", width: 120)
        expect(html).to include("opts%5Balt%5D=portrait")
        expect(html).to include("opts%5Bwidth%5D=120")
      end

      it "encodes kind=image for image_tag" do
        html = helper.image_tag(variant, async: true)
        expect(html).to include("kind=image")
      end

      it "video_tag encodes kind=video" do
        html = helper.video_tag(variant, async: true, controls: true)
        expect(html).to include("<turbo-frame")
        expect(html).to include("kind=video")
      end

      it "prefills the turbo-frame with a placeholder <img> using the polymorphic URL" do
        html = helper.image_tag(variant, async: true, alt: "portrait")
        # Initial paint provides valid <img> markup so layout sizing works
        # and consumers' tests that read img[:src] keep functioning. Turbo
        # replaces this with the state partial on first frame fetch.
        expect(html).to include("<img")
        expect(html).to include('alt="portrait"')
        expect(html).to match(%r{<img [^>]*src="[^"]*/rails/active_storage/representations/[^"]+"})
      end

      it "prefills the turbo-frame with a placeholder <video> for video_tag" do
        html = helper.video_tag(variant, async: true, controls: true)
        expect(html).to include("<video")
        expect(html).to match(%r{<video [^>]*src="[^"]*/rails/active_storage/representations/[^"]+"})
      end
    end

    context "with async: true for a processed variant" do
      before { simulate_processed_variant(variant) }

      it "emits a plain <img> with the polymorphic URL (no turbo-frame)" do
        html = helper.image_tag(variant, async: true)
        expect(html).to include("<img")
        expect(html).not_to include("turbo-frame")
      end

      it "with direct: true uses the direct CDN URL" do
        ActiveStorage::AsyncVariants.cdn_host = "https://cdn.example.com"
        html = helper.image_tag(variant, async: true, direct: true)
        expect(html).to include("src=\"https://cdn.example.com/#{variant.key}\"")
        expect(html).not_to include("turbo-frame")
      end

      it "video_tag emits a plain <video> with the resolved src (no turbo-frame)" do
        html = helper.video_tag(variant, async: true, controls: true)
        expect(html).to include("<video")
        expect(html).not_to include("turbo-frame")
      end
    end

    context "with direct: true only (no async:)" do
      it "uses the storage service URL when processed and no cdn_host" do
        simulate_processed_variant(variant)
        html = helper.image_tag(variant, direct: true)
        expect(html).to include("/rails/active_storage/disk/")
      end

      it "uses the configured cdn_host when processed" do
        ActiveStorage::AsyncVariants.cdn_host = "https://cdn.example.com"
        simulate_processed_variant(variant)
        html = helper.image_tag(variant, direct: true)
        expect(html).to include("src=\"https://cdn.example.com/#{variant.key}\"")
      end

      it "falls back to the Rails representation URL when not processed" do
        html = helper.image_tag(variant, direct: true)
        expect(html).to include("/rails/active_storage/representations/")
      end
    end

    it "video_tag passes through without async/direct" do
      html = helper.video_tag(variant, controls: true)
      expect(html).not_to include("turbo-frame")
    end
  end
end
