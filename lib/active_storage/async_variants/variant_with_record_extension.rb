# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariantWithRecordExtension
      def processed
        if blob.bucket_backed?
          enqueue_processing unless processed? || processing?
          self
        else
          super
        end
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

      private

      def resolved_async_options
        @resolved_async_options ||=
          variation.async_options.presence ||
          ActiveStorage::AsyncVariants::Registry[variation.digest] ||
          {}
      end

      def active_fallback
        if failed?
          resolved_async_options.fetch(:failed) { resolved_async_options[:processing] }
        else
          resolved_async_options[:processing]
        end
      end

      def enqueue_processing
        result = find_named_async_variant
        return unless result
        attachment, variant_name, _ = result

        return if async_record

        blob.variant_records.create!(
          variation_digest: variation.digest,
          state: "pending",
        )

        ActiveStorage::AsyncVariants::ProcessJob.perform_later(
          attachment.record, attachment.name, variant_name.to_s,
        )
      rescue ActiveRecord::RecordNotUnique
        # another caller won the race; their job will handle processing
      end

      # Cold-path scan: only used by enqueue_processing, which needs the
      # (attachment.record, attachment.name, variant_name) tuple to dispatch
      # ProcessJob -- more than the digest registry stores. Hot-path URL
      # resolution goes through Registry, not this method.
      def find_named_async_variant
        target = variation.transformations.to_json

        blob.attachments.each do |attachment|
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
