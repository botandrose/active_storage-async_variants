# frozen_string_literal: true

require_relative "async_variants/version"
require_relative "async_variants/transformer"
require_relative "async_variants/variation_extension"
require_relative "async_variants/variant_with_record_extension"
require_relative "async_variants/attachment_extension"
require_relative "async_variants/process_job"

module ActiveStorage
  module AsyncVariants
    class Engine < ::Rails::Engine
      config.after_initialize do
        ActiveStorage::Variation.prepend(
          ActiveStorage::AsyncVariants::VariationExtension
        )
        ActiveStorage::VariantWithRecord.prepend(
          ActiveStorage::AsyncVariants::VariantWithRecordExtension
        )
        ActiveStorage::Attachment.prepend(
          ActiveStorage::AsyncVariants::AttachmentExtension
        )
      end
    end

    def self.callback_token_for(variant_record)
      ActiveStorage.verifier.generate(variant_record.id, purpose: :async_variant_callback)
    end

    def self.callback_url_for(variant_record)
      token = callback_token_for(variant_record)
      Rails.application.routes.url_helpers.active_storage_async_variant_callback_url(
        token: token,
        **ActiveStorage::Current.url_options,
      )
    end
  end
end
