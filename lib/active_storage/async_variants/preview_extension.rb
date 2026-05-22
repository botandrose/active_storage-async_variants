# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module PreviewExtension
      # Enqueue (or no-op if already done) the same ProcessJob the
      # VariantWithRecord path uses, so Preview-side and VariantWithRecord-side
      # processing converge on a single record-and-job machinery rather than
      # the gem's earlier two-path design (one writing to preview_image's
      # variant_records, one to the original blob's).
      def processed
        if async_preview?
          enqueue_async_preview unless preview_variant_processed?
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
        find_preview_variant_record&.state == "processed"
      end

      # ProcessJob stores variant_records on the source blob (i.e. @variant.blob,
      # which for a named variant declared on a previewable attachment is the
      # original blob -- not preview_image.blob). Read from the same place.
      def find_preview_variant_record
        blob.variant_records.find_by(variation_digest: variation.digest)
      end

      # Delegate to the named-variant VariantWithRecord so we go through the
      # exact same enqueue_processing + ProcessJob machinery as direct
      # variant calls. Skips silently if no matching named variant exists,
      # which can happen for raw transformations that don't correspond to
      # any declared async variant. Also skipped on non-bucket services,
      # where the gem defers to vanilla ActiveStorage and dispatching here
      # would synchronously transform via vips (broken for video blobs).
      def enqueue_async_preview
        return unless blob.bucket_backed?
        target = variation.transformations.to_json
        blob.attachments.each do |attachment|
          attachment.send(:named_variants).each do |name, _|
            candidate = attachment.variant(name.to_sym)
            next unless candidate.variation.transformations.to_json == target
            next unless candidate.variation.async_options[:processing].present?
            candidate.processed
            return
          end
        end
      end

      def fallback_preview_url(...)
        case active_fallback
        when :original then blob.url(...)
        when :blank then nil
        when Proc then active_fallback.call(blob)
        when String then active_fallback
        end
      end

      def active_fallback
        if failed?
          resolved_async_options.fetch(:failed) { resolved_async_options[:processing] }
        else
          resolved_async_options[:processing]
        end
      end

      def failed?
        find_preview_variant_record&.state == "failed"
      end
    end
  end
end
