# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module PreviewExtension
      def processed
        async_preview? ? self : super
      end

      def process
        if async_preview?
          resolved_async_options[:transformer].new.process_preview(blob: blob, variation: variation) unless blob.preview_image.attached?
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

      def async_state
        return nil unless async_preview?
        return "pending" unless blob.preview_image.attached?
        find_preview_variant_record&.state || "pending"
      end

      private

      def async_preview?
        resolved_async_options[:transformer].present?
      end

      # Variations rebuilt from the redirect URL only carry transformations --
      # :transformer / :processing / :failed are stripped at Variation#initialize
      # and not embedded in the URL key. Recover them via the digest-keyed
      # registry that VariationExtension warms on every view-side variant call.
      def resolved_async_options
        @resolved_async_options ||=
          variation.async_options.presence ||
          ActiveStorage::AsyncVariants::Registry[variation.digest] ||
          {}
      end

      def preview_variant_processed?
        blob.preview_image.attached? && find_preview_variant_record&.state == "processed"
      end

      def find_preview_variant_record
        blob.preview_image.blob.variant_records.find_by(variation_digest: variation.digest)
      end

      def fallback_preview_url(...)
        case resolved_async_options[:processing]
        when :original then blob.url(...)
        when :blank then nil
        when Proc then resolved_async_options[:processing].call(blob)
        when String then resolved_async_options[:processing]
        end
      end
    end
  end
end
