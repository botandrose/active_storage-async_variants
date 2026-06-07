# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariantWithRecordExtension
      # Block vanilla ActiveStorage's synchronous transform on bucket-backed
      # services; rely on the auto-enqueue (AttachmentExtension) path -- and the
      # public #enqueue! -- to dispatch ProcessJob.
      def processed
        blob.bucket_backed? ? self : super
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

      def url(...)
        if blob.bucket_backed? && !processed?
          fallback = active_fallback
          case fallback
          when :original then blob.url(...)
          when :blank then nil
          when Proc then fallback.call(blob)
          when String then fallback
          else super
          end
        else
          super
        end
      end

      def processed?
        if blob.bucket_backed?
          async_record&.state == "processed"
        else
          super
        end
      end

      def processing?
        async_record&.state == "processing"
      end

      def pending?
        async_record.nil? || async_record.state == "pending"
      end

      def failed?
        async_record&.state == "failed"
      end

      def error
        async_record&.error
      end

      def async_state
        return nil unless blob.bucket_backed?
        async_record&.state || "pending"
      end

      def progress
        async_record&.progress
      end

      def progress_known?
        !async_record&.progress.nil?
      end

      def last_heartbeat_at
        async_record&.last_heartbeat_at
      end

      private

      def resolved_async_options
        @resolved_async_options ||=
          variation.async_options.presence ||
          ActiveStorage::AsyncVariants::Registry[variation.digest] ||
          find_named_async_variant&.dig(2) ||
          {}
      end

      def active_fallback
        if failed?
          resolved_async_options.fetch(:failed) { resolved_async_options[:processing] }
        else
          resolved_async_options[:processing]
        end
      end

      # Cold-path scan: used by enqueue! (which needs the attachment +
      # variant_name to dispatch ProcessJob) and by resolved_async_options as
      # a fallback when the Registry is cold (e.g. in dev, when a
      # RepresentationsRedirectController request hits a worker that hasn't
      # autoloaded the consumer model yet).
      #
      # Walks one level through preview_image attachments so a request for
      # a Variant of a video's extracted preview frame can still find the
      # named variant declared on the parent record's source-video field.
      def find_named_async_variant
        target = variation.transformations.to_json
        scan_for_named_variant(blob, target)
      end

      def scan_for_named_variant(blob_to_scan, target, depth: 0)
        blob_to_scan.attachments.each do |attachment|
          if attachment.name == "preview_image" && attachment.record_type == "ActiveStorage::Blob" && depth < 1
            source = ActiveStorage::Blob.find_by(id: attachment.record_id)
            result = source && scan_for_named_variant(source, target, depth: depth + 1)
            return result if result
            next
          end

          attachment.send(:named_variants).each do |name, _|
            candidate = attachment.variant(name.to_sym)
            if candidate.variation.transformations.to_json == target
              return [attachment, name, candidate.variation.async_options] if candidate.variation.async_options[:processing].present?
            end
          end
        end
        nil
      end

      def async_record
        blob.variant_records.find_by(variation_digest: variation.digest)
      end
    end
  end
end
