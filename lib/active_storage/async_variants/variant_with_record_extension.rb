# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariantWithRecordExtension
      def url(...)
        if processed?
          super
        else
          fallback_url(...)
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
        async? ? ready? : super
      end

      def async?
        variation.async_options[:fallback].present?
      end

      def async_record
        blob.variant_records.find_by(variation_digest: variation.digest)
      end

      def fallback_url(...)
        case variation.async_options[:fallback]
        when :original
          blob.url(...)
        when :blank
          nil
        when Proc
          variation.async_options[:fallback].call(blob)
        end
      end
    end
  end
end
