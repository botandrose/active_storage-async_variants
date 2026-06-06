# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    # Prepended onto ActionView::Helpers::AssetTagHelper. Adds `async:` and
    # `direct:` options to image_tag/video_tag; routes unprocessed variants
    # through a <turbo-frame> whose body lives in StatesController#show.
    module AssetTagHelperExtension
      include ActiveStorage::AsyncVariants::Helper

      def image_tag(source, options = {})
        async_variant_tag(:image, [source], options) do |urls, opts|
          super(urls.first, opts)
        end
      end

      def video_tag(*sources)
        options = sources.extract_options!
        async_variant_tag(:video, sources, options) do |urls, opts|
          super(*urls, opts)
        end
      end

      private

      def async_variant_tag(kind, sources, options)
        options = options.symbolize_keys
        async = options.delete(:async)
        direct = options.delete(:direct)
        return yield(sources, options) if !async && !direct

        variant, *rest = sources
        assert_async_variant!(variant)

        if async && !async_variant_processed_inline?(variant)
          async_variant_turbo_frame(variant, kind:, direct:, html_options: options)
        else
          yield [async_variant_resolved_src(variant, direct:), *rest], options
        end
      end

      def assert_async_variant!(source)
        unless source.is_a?(ActiveStorage::VariantWithRecord) || source.is_a?(ActiveStorage::Preview)
          raise ArgumentError, "image_tag/video_tag with async:/direct: requires an ActiveStorage::VariantWithRecord or Preview, got #{source.class}"
        end
      end

      def async_variant_turbo_frame(variant, kind:, direct:, html_options:)
        content_tag(
          :"turbo-frame",
          "",
          id: async_variant_frame_id(variant),
          src: async_variant_frame_src(variant, kind: kind, direct: direct, html_options: html_options),
          refresh: "morph",
        )
      end
    end
  end
end
