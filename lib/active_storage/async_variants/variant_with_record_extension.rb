# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariantWithRecordExtension
      def processed
        if blob.service.respond_to?(:bucket)
          enqueue_processing unless ready? || processing?
          self
        else
          super
        end
      end

      def url(...)
        if blob.service.respond_to?(:bucket) && !ready?
          fallback = resolved_async_options[:fallback]
          case fallback
          when :original then blob.url(...)
          when :blank then nil
          when Proc then fallback.call(blob)
          else blob.url(...)
          end
        else
          super
        end
      end

      def ready?
        async_record&.state == "processed"
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

      private

      def processed?
        blob.service.respond_to?(:bucket) ? ready? : super
      end

      def resolved_async_options
        return @resolved_async_options if defined?(@resolved_async_options)
        @resolved_async_options = find_async_options
      end

      def find_async_options
        return variation.async_options if variation.async_options[:fallback].present?
        find_named_async_variant&.last || {}
      end

      def enqueue_processing
        result = find_named_async_variant
        return unless result
        attachment, variant_name, _ = result

        existing = async_record
        if existing && existing.state != "failed"
          return
        end

        if existing
          existing.update!(state: "pending", error: nil)
        else
          blob.variant_records.create!(
            variation_digest: variation.digest,
            state: "pending",
          )
        end

        ActiveStorage::AsyncVariants::ProcessJob.perform_later(
          attachment.record, attachment.name, variant_name.to_s,
        )
      rescue ActiveRecord::RecordNotUnique
        # another caller won the race; their job will handle processing
      end

      def find_named_async_variant
        target = variation.transformations.to_json

        blob.attachments.each do |attachment|
          attachment.send(:named_variants).each do |name, _|
            candidate = attachment.variant(name.to_sym)
            if candidate.variation.transformations.to_json == target
              return [attachment, name, candidate.variation.async_options] if candidate.variation.async_options[:fallback].present?
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
