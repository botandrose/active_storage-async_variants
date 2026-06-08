# frozen_string_literal: true

module ActiveStorage
  module AsyncVariants
    class StatesController < ActiveStorage::AsyncVariants.parent_controller.constantize
      # signed_blob_id + variation_key in URL act as CSRF: both require app's secret.
      skip_forgery_protection

      helper "turbo/frames"
      helper ActiveStorage::AsyncVariants::Helper

      layout false

      # 1x1 transparent GIF served at a filename-bearing URL, so the
      # processing/failed <img> identifies its media without fetching anything.
      TRANSPARENT_GIF = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7".unpack1("m").freeze

      before_action :set_variant, only: %i[show retry]

      def show
      end

      def placeholder
        expires_in 1.year, public: true
        send_data TRANSPARENT_GIF, type: "image/gif", disposition: "inline"
      end

      def retry
        @variant.blob.variant_records.where(
          variation_digest: @variant.variation.digest,
          state: "failed",
        ).destroy_all
        @variant.enqueue!

        redirect_to Rails.application.routes.url_helpers.async_variant_state_path(
          signed_blob_id: params[:signed_blob_id],
          variation_key: params[:variation_key],
          kind: params[:kind],
          direct: params[:direct],
          opts: async_variant_html_options.presence,
        ), status: :see_other
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
