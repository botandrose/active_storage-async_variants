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
        if result = find_named_async_variant
          attachment, variant_name, _ = result

          blob.variant_records.create!(
            variation_digest: variation.digest,
            state: "pending",
          )
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
      # :transformer / :processing / :failed are stripped at Variation#initialize
      # and not embedded in the URL key. Recover them via the digest-keyed
      # registry that VariationExtension warms on every view-side variant call,
      # or fall back to scanning attached named variants when the registry is
      # cold (autoloader hasn't touched the consumer model yet).
      def resolved_async_options
        @resolved_async_options ||=
          variation.async_options.presence ||
          ActiveStorage::AsyncVariants::Registry[variation.digest] ||
          find_named_async_variant&.dig(2) ||
          {}
      end

      def find_named_async_variant
        target = variation.transformations.to_json
        blob.attachments.each do |attachment|
          attachment.send(:named_variants).each do |name, _|
            candidate = attachment.variant(name.to_sym)
            next unless candidate.variation.transformations.to_json == target
            return [attachment, name, candidate.variation.async_options] if candidate.variation.async_options[:transformer].present?
          end
        end
        nil
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
