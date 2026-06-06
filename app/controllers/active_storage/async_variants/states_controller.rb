# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    class StatesController < ActiveStorage::AsyncVariants.parent_controller.constantize
      # signed_blob_id + variation_key in URL act as CSRF: both require app's secret.
      skip_forgery_protection

      helper "turbo/frames"
      helper ActiveStorage::AsyncVariants::Helper

      layout false

      before_action :set_variant

      def show
      end

      helper_method :async_variant_kind, :async_variant_direct?, :async_variant_html_options

      private

      def set_variant
        blob = ActiveStorage::Blob.find_signed!(params[:signed_blob_id])
        variation = ActiveStorage::Variation.decode(params[:variation_key])
        @variant = blob.variant(variation)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        head :not_found
      end

      def async_variant_kind
        params[:kind].to_s == "video" ? :video : :image
      end

      def async_variant_direct?
        ActiveModel::Type::Boolean.new.cast(params[:direct])
      end

      def async_variant_html_options
        params[:opts]
          &.permit(*ActiveStorage::AsyncVariants::PASS_THROUGH_HTML_OPTIONS)
          .to_h
      end
    end
  end
end
