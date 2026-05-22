# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module AssetTagHelperExtension
      def image_tag(source, options = {})
        options = options.symbolize_keys
        async = options.delete(:async)
        direct = options.delete(:direct)
        return super if !async && !direct
        variant = AssetTagHelperExtension.coerce_variant!(source)
        src = AssetTagHelperExtension.resolve_src(variant, direct: direct)
        AssetTagHelperExtension.apply_async_data!(options, variant: variant, direct: direct) if async
        super(src, options)
      end

      def video_tag(*sources)
        options = sources.extract_options!.symbolize_keys
        async = options.delete(:async)
        direct = options.delete(:direct)
        return super(*sources, options) if !async && !direct
        variant = AssetTagHelperExtension.coerce_variant!(sources.first)
        sources[0] = AssetTagHelperExtension.resolve_src(variant, direct: direct)
        AssetTagHelperExtension.apply_async_data!(options, variant: variant, direct: direct) if async
        super(*sources, options)
      end

      class << self
        def coerce_variant!(source)
          unless source.is_a?(ActiveStorage::VariantWithRecord) || source.is_a?(ActiveStorage::Preview)
            raise ArgumentError, "image_tag/video_tag with async:/direct: requires an ActiveStorage::VariantWithRecord or Preview, got #{source.class}"
          end
          source
        end

        def resolve_src(variant, direct:)
          if direct && variant.async_state == "processed"
            direct_url(variant)
          else
            # Idempotent: enqueue ProcessJob if no record exists yet so a
            # never-touched variant doesn't sit pending forever. Gated on
            # bucket-backed services -- on Disk/Test the gem defers to
            # vanilla ActiveStorage, and #processed would run a synchronous
            # transform (e.g. vips on an mp4) that the external transformer
            # is supposed to handle.
            variant.processed if variant.blob.bucket_backed?
            polymorphic_url(variant)
          end
        end

        def apply_async_data!(options, variant:, direct:)
          data = (options[:data] || {}).symbolize_keys
          controllers = data[:controller].to_s.split
          controllers << "async-variant" unless controllers.include?("async-variant")
          data[:controller] = controllers.join(" ")
          data[:async_variant_src_value] = polymorphic_url(variant)
          data[:async_variant_state_value] = variant.async_state
          data[:async_variant_direct_value] = direct_url(variant) if direct && variant.async_state == "processed"
          options[:data] = data
        end

        def direct_url(variant)
          if cdn = ActiveStorage::AsyncVariants.cdn_host
            "#{cdn}/#{variant.key}"
          else
            variant.image.url
          end
        end

        def polymorphic_url(variant)
          url_options = ActiveStorage::Current.url_options || Rails.application.routes.default_url_options
          Rails.application.routes.url_helpers.polymorphic_url(variant, **url_options)
        end
      end
    end
  end
end
