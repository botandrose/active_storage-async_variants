# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    module VariantWithRecordExtension
      def url(...)
        if async_active? && !processed?
          fallback_url(...)
        else
          super
        end
      end

      def process
        if async? && blob.service.respond_to?(:bucket) && (transformer_class = variation.async_options[:transformer])
          process_with_transformer(transformer_class)
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
        async_active? ? ready? : super
      end

      def async?
        variation.async_options[:fallback].present?
      end

      def async_active?
        async? && blob.service.respond_to?(:bucket)
      end

      def async_record
        blob.variant_records.find_by(variation_digest: variation.digest)
      end

      def process_with_transformer(transformer_class)
        transformer = transformer_class.new
        variant_record = blob.variant_records.create_or_find_by!(variation_digest: variation.digest)
        return self if variant_record.state.in?(%w[processing processed])
        variant_record.update!(state: "processing")

        if transformer.inline?
          blob.open do |file|
            result = transformer.process(file, **variation.transformations)
            variant_record.image.attach(
              io: result[:io], filename: result[:filename],
              content_type: result[:content_type], service_name: blob.service.name,
            )
            variant_record.update!(state: "processed")
          end
        else
          callback_url = ActiveStorage::AsyncVariants.callback_url_for(variant_record)
          transformer.initiate(
            source_url: blob.url, callback_url: callback_url,
            variant_record_id: variant_record.id, **variation.transformations,
          )
        end
        self
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
