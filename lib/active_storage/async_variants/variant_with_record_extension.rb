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
        if blob.bucket_backed? && async_variant? && !processed?
          blob.url(...)
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

      # Percent-per-second observed so far (progress over elapsed processing
      # time); drives the progress-bar's optimistic creep between reloads.
      def progress_rate
        record = async_record
        return nil unless record&.created_at && record.last_heartbeat_at && record.progress&.positive?
        elapsed = record.last_heartbeat_at - record.created_at
        elapsed.positive? ? (record.progress / elapsed).round(4) : nil
      end

      private

      def async_variant?
        resolved_async_options[:transformer].present?
      end

      def resolved_async_options
        @resolved_async_options ||=
          variation.async_options.presence ||
          ActiveStorage::AsyncVariants::Registry[variation.digest] ||
          find_named_async_variant&.dig(2) ||
          {}
      end

      # Cold-path scan: used by enqueue! (which needs the attachment +
      # variant_name to dispatch ProcessJob) and by resolved_async_options as
      # a fallback when the Registry is cold (e.g. in dev, when a
      # RepresentationsRedirectController request hits a worker that hasn't
      # autoloaded the consumer model yet).
      def find_named_async_variant
        ActiveStorage::AsyncVariants::NamedVariantScan.find(blob, variation)
      end

      def async_record
        blob.variant_records.find_by(variation_digest: variation.digest)
      end
    end
  end
end
