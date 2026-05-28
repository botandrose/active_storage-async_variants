# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    class CallbacksController < ActionController::API
      def create
        variant_record_id = ActiveStorage.verifier.verify(params[:token], purpose: :async_variant_callback)
        variant_record = ActiveStorage::VariantRecord.find(variant_record_id)

        case params[:status]
        when "success"
          variant_record.update!(state: "processed")
          apply_reported_metadata(variant_record, params)
        when "failed"
          variant_record.update!(state: "failed", error: params[:error])
        else
          head :unprocessable_entity and return
        end

        head :ok
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        head :unauthorized
      end

      private

      # External transformers (Crucible) write the file directly to the bucket
      # and report its byte_size/checksum on the success callback. Reconcile the
      # placeholder blobs created with byte_size: 0, checksum: "0" -- the variant
      # itself, and (for video previews) the extracted frame on the source blob.
      def apply_reported_metadata(variant_record, params)
        reconcile(variant_record.image.blob, params[:byte_size], params[:checksum])
        reconcile(variant_record.blob, params[:preview_image_byte_size], params[:preview_image_checksum])
      end

      # The placeholder sentinels (byte_size 0, checksum "0") gate each field, so
      # this is idempotent and never overwrites a real source blob's metadata.
      def reconcile(blob, byte_size, checksum)
        return unless blob

        attrs = {}
        if (bytes = positive_int(byte_size)) && blob.byte_size.zero?
          attrs[:byte_size] = bytes
        end
        if checksum.present? && checksum != "0" && blob.checksum == "0"
          attrs[:checksum] = checksum
        end
        blob.update!(attrs) if attrs.any?
      end

      def positive_int(value)
        int = value.to_i
        int.positive? ? int : nil
      end
    end
  end
end
