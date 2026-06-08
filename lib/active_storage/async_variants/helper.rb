# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    # View/controller helper methods. Included in the AssetTagHelperExtension
    # (so image_tag/video_tag can use them) and added to StatesController via
    # `helper ActiveStorage::AsyncVariants::Helper` (so the state partials can
    # use them).
    module Helper
      # 1x1 transparent GIF: reserves the variant's box without fetching the
      # original through the representations path on every poll.
      PLACEHOLDER_SRC = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

      def async_variant_placeholder_tag(variant, html_options = {}, kind: :image)
        opts = async_variant_box_dimensions(variant)
          .merge(html_options.symbolize_keys.except(:src, :controls, :autoplay, :preload, :poster))
        # A video placeholder carries no <source>, so it reserves the box
        # without loading anything -- same zero-network intent as the GIF.
        kind == :video ? content_tag(:video, "", opts) : image_tag(PLACEHOLDER_SRC, opts)
      end

      def async_variant_box_dimensions(variant)
        resize = variant.variation.transformations
          .values_at(:resize_to_limit, :resize_to_fit, :resize_to_fill)
          .compact.first
        resize.is_a?(Array) ? { width: resize[0], height: resize[1] } : {}
      end

      # In test with non-bucket-backed services, the gem defers to vanilla
      # ActiveStorage (synchronous vips transform) -- inline rendering keeps
      # those environments simple. Otherwise, only inline a normal <img> when
      # the variant has reached the processed terminal state.
      def async_variant_processed_inline?(variant)
        !variant.blob.bucket_backed? || variant.async_state == "processed"
      end

      def async_variant_resolved_src(variant, direct:)
        if direct && variant.async_state == "processed"
          async_variant_direct_url(variant)
        else
          variant.processed if variant.blob.bucket_backed?
          async_variant_representation_path(variant)
        end
      end

      def async_variant_frame_id(variant)
        digest = variant.variation.digest.gsub(/[^a-zA-Z0-9_-]/, "")
        "async-variant-#{variant.blob.id}-#{digest}"
      end

      def async_variant_frame_src(variant, kind:, direct:, html_options: {})
        async_variant_state_path(
          signed_blob_id: variant.blob.signed_id,
          variation_key: variant.variation.key,
          kind:,
          direct:,
          opts: html_options.slice(*PASS_THROUGH_HTML_OPTIONS),
        )
      end

      def async_variant_direct_url(variant)
        if cdn = ActiveStorage::AsyncVariants.cdn_host
          "#{cdn}/#{variant.key}"
        else
          variant.image.url
        end
      end

      def async_variant_representation_path(variant)
        Rails.application.routes.url_helpers.rails_blob_representation_path(
          variant.blob.signed_id,
          variant.variation.key,
          variant.blob.filename.to_s,
        )
      end
    end
  end
end
