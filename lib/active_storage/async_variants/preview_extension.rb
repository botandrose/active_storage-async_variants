# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module PreviewExtension
      # Block vanilla ActiveStorage's synchronous preview transform on
      # async-backed services; rely on the auto-enqueue (AttachmentExtension)
      # path -- and the public #enqueue! -- to dispatch ProcessJob.
      def processed
        async_preview? ? self : super
      end

      def enqueue!
        return if find_preview_variant_record

        if result = ActiveStorage::AsyncVariants::NamedVariantScan.find(blob, variation)
          attachment, variant_name, options = result

          transformer = options[:transformer]
          if transformer&.new&.external?
            ActiveStorage::AsyncVariants.ensure_preview_image_placeholder!(blob)
            blob.preview_image.blob.variant_records.create!(
              variation_digest: variant.variation.digest,
              state: "pending",
            )
          end
          ActiveStorage::AsyncVariants::ProcessJob.perform_later(
            attachment.record, attachment.name, variant_name.to_s,
          )
        end
      rescue ActiveRecord::RecordNotUnique
        # another caller (or a leftover record) wins; their job handles it
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

      def progress
        find_preview_variant_record&.progress
      end

      def progress_known?
        !find_preview_variant_record&.progress.nil?
      end

      def last_heartbeat_at
        find_preview_variant_record&.last_heartbeat_at
      end

      private

      def async_preview?
        resolved_async_options[:transformer].present?
      end

      # Variations rebuilt from the redirect URL only carry transformations --
      # :transformer is stripped at Variation#initialize and not
      # embedded in the URL key. Recover it via the digest-keyed registry that
      # VariationExtension warms on every view-side variant call, or fall back to
      # scanning attached named variants when the registry is cold (autoloader
      # hasn't touched the consumer model yet).
      def resolved_async_options
        @resolved_async_options ||=
          variation.async_options.presence ||
          ActiveStorage::AsyncVariants::Registry[variation.digest] ||
          ActiveStorage::AsyncVariants::NamedVariantScan.find(blob, variation)&.dig(2) ||
          {}
      end

      def preview_variant_processed?
        find_preview_variant_record&.state == "processed"
      end

      # Stock preview structure: variant records hang off the extracted frame
      # (the blob's preview_image attachment), not the source blob. The digest
      # is resolved through stock's Preview#variant so it matches the
      # default_to-applied variation embedded in representation URLs.
      def find_preview_variant_record
        return nil unless blob.preview_image.attached?
        blob.preview_image.blob.variant_records.find_by(variation_digest: variant.variation.digest)
      end

      # Serve the original until the preview variant is processed.
      def fallback_preview_url(...)
        blob.url(...)
      end
    end
  end
end
