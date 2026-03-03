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
        when "failed"
          variant_record.update!(state: "failed", error: params[:error])
        else
          head :unprocessable_entity and return
        end

        head :ok
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        head :unauthorized
      end
    end
  end
end
