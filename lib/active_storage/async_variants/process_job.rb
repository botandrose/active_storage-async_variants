# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    class ProcessJob < ActiveJob::Base
      retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
        job.logger.error "AsyncVariants: permanently failed: #{error.message}"
      end

      def perform(record, attachment_name, variant_name)
        attachment = record.public_send(attachment_name)
        @variant = attachment.variant(variant_name.to_sym)
        variation = @variant.variation
        @async_options = variation.async_options
        transformer_class = @async_options[:transformer]
        blob = @variant.blob

        @variant_record = blob.variant_records.create_or_find_by!(variation_digest: variation.digest)
        @variant_record.update!(state: "processing")

        if transformer_class
          transformer = transformer_class.new
          if transformer.inline?
            process_inline(blob, @variant_record, transformer, variation)
          else
            process_external(blob, @variant_record, transformer, variation)
          end
        else
          process_default(blob, @variant_record, variation)
        end
      rescue => e
        @variant_record&.update!(
          state: "failed",
          error: e.message,
          attempts: (@variant_record&.attempts || 0) + 1,
        )
        raise
      end

      private

      def process_inline(blob, variant_record, transformer, variation)
        options = variation.transformations

        blob.open do |file|
          result = transformer.process(file, **options)
          variant_record.image.attach(
            io: result[:io],
            filename: result[:filename],
            content_type: result[:content_type],
            service_name: blob.service.name,
          )
          variant_record.update!(state: "processed")
        end
      end

      def process_default(blob, variant_record, variation)
        blob.open do |input|
          variation.transform(input) do |output|
            variant_record.image.attach(
              io: output,
              filename: "#{blob.filename.base}.#{variation.format.downcase}",
              content_type: variation.content_type,
              service_name: blob.service.name,
            )
          end
        end
        variant_record.update!(state: "processed")
      end

      def process_external(blob, variant_record, transformer, variation)
        options = variation.transformations
        callback_url = ActiveStorage::AsyncVariants.callback_url_for(variant_record)
        source_url = blob.url

        transformer.initiate(
          source_url: source_url,
          callback_url: callback_url,
          variant_record_id: variant_record.id,
          **options,
        )
      end
    end
  end
end
