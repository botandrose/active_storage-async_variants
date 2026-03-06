# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module PreviewExtension
      def processed
        async_preview? ? self : super
      end

      def process
        if async_preview?
          variation.async_options[:transformer].new.process_preview(blob: blob, variation: variation) unless blob.preview_image.attached?
          self
        else
          super
        end
      end

      def processed?
        async_preview? ? preview_variant_processed? : super
      end

      def url(...)
        if async_preview?
          preview_variant_processed? ? find_preview_variant_record.image.url(...) : fallback_preview_url(...)
        else
          super
        end
      end

      def key
        if async_preview?
          raise ActiveStorage::Preview::UnprocessedError unless preview_variant_processed?
          find_preview_variant_record.image.blob.key
        else
          super
        end
      end

      private

      def async_preview?
        variation.async_options[:transformer].present?
      end

      def preview_variant_processed?
        blob.preview_image.attached? && find_preview_variant_record&.state == "processed"
      end

      def find_preview_variant_record
        blob.preview_image.blob.variant_records.find_by(variation_digest: variation.digest)
      end

      def fallback_preview_url(...)
        case variation.async_options[:fallback]
        when :original then blob.url(...)
        when :blank then nil
        when Proc then variation.async_options[:fallback].call(blob)
        end
      end
    end
  end
end
