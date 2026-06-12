# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    class ProcessJob < ActiveJob::Base
      retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
        job.logger.error "AsyncVariants: permanently failed: #{error.message}"
      end

      def perform(record, attachment_name, variant_name)
        attachment = record.public_send(attachment_name)
        representation = attachment.representation(variant_name.to_sym)

        if representation.is_a?(ActiveStorage::Preview)
          perform_preview(representation)
        else
          perform_variant(representation)
        end
      rescue => e
        @variant_record&.update!(
          state: "failed",
          error: e.message.to_s.truncate(16_000),
          attempts: (@variant_record&.attempts || 0) + 1,
        )
        raise
      end

      private

      def perform_variant(variant)
        blob = variant.blob
        @variant_record = blob.variant_records.create_or_find_by!(variation_digest: variant.variation.digest)
        @variant_record.update!(state: "processing")

        dispatch(variant.variation, transform_blob: blob, source_blob: blob)
      end

      # Stock preview structure: the frame lives as a preview_image attachment
      # on the source blob, and the variant record hangs off the frame blob.
      # Inline/default transformers need the real frame up front (the stock
      # previewer extracts it); external transformers get a placeholder the
      # service writes into, plus the source blob to extract from.
      def perform_preview(preview)
        blob = preview.blob
        transformer_class = preview.variation.async_options[:transformer]

        if transformer_class.nil? || transformer_class.new.inline?
          preview.send(:process) unless blob.preview_image.attached?
        else
          ActiveStorage::AsyncVariants.ensure_preview_image_placeholder!(blob)
        end

        frame_blob = blob.preview_image.blob
        variation = preview.send(:variant).variation
        @variant_record = frame_blob.variant_records.create_or_find_by!(variation_digest: variation.digest)
        @variant_record.update!(state: "processing")

        dispatch(variation, transform_blob: frame_blob, source_blob: blob)
      end

      def dispatch(variation, transform_blob:, source_blob:)
        transformer_class = variation.async_options[:transformer]

        if transformer_class
          transformer = transformer_class.new
          if transformer.inline?
            process_inline(transform_blob, @variant_record, transformer, variation)
          else
            process_external(source_blob, @variant_record, transformer, variation)
          end
        else
          process_default(transform_blob, @variant_record, variation)
        end
      end

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

        # Seed the heartbeat so a transform that dies before its first heartbeat
        # still goes stale, then arm the watchdog.
        variant_record.touch(:last_heartbeat_at)
        ActiveStorage::AsyncVariants::HeartbeatWatchdogJob
          .set(wait: ActiveStorage::AsyncVariants.heartbeat_stale_after)
          .perform_later(variant_record)
      end
    end
  end
end
