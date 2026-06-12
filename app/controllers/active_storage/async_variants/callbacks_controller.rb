# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    class CallbacksController < ActionController::API
      def create
        case params[:status]
        when "success"
          variant_record.update!(state: "processed")
          apply_reported_metadata(variant_record, params)
        when "progress"
          ActiveStorage::VariantRecord
            .where(id: variant_record.id, state: %w[pending processing])
            .update_all(progress: params[:percent].to_i.clamp(0, 100), last_heartbeat_at: Time.current)
        when "failed"
          # error column is TEXT (64KB); utf8mb4 is up to 4 bytes/char, so cap at 16k chars.
          variant_record.update!(state: "failed", error: params[:error].to_s.truncate(16_000))
        else
          head :unprocessable_entity and return
        end

        head :ok
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        head :unauthorized
      end

      private

      def variant_record
        @variant_record ||= begin
          variant_record_id = ActiveStorage.verifier.verify(params[:token], purpose: :async_variant_callback)
          ActiveStorage::VariantRecord.find(variant_record_id)
        end
      end

      def apply_reported_metadata(variant_record, params)
        reconcile(variant_record.image.blob, params[:byte_size], params[:checksum])
        reconcile(variant_record.blob, params[:preview_image_byte_size], params[:preview_image_checksum])
      end

      def reconcile(blob, byte_size, checksum)
        return unless blob

        if positive_int?(byte_size) && blob.byte_size.zero?
          blob.byte_size = byte_size
        end
        if checksum.present? && blob.checksum == "0"
          blob.checksum = checksum
        end
        blob.save!

        if blob.checksum != "0"
          blob.mirror_later
        end
      end

      def positive_int?(value)
        value.to_i.positive?
      end
    end
  end
end
