# frozen_string_literal: true

require_relative "async_variants/version"
require_relative "async_variants/transformer"
require_relative "async_variants/registry"
require_relative "async_variants/named_variant_scan"
require_relative "async_variants/blob_extension"
require_relative "async_variants/variation_extension"
require_relative "async_variants/variant_with_record_extension"
require_relative "async_variants/variant_record_extension"
require_relative "async_variants/preview_extension"
require_relative "async_variants/attachment_extension"
require_relative "async_variants/reflection_extension"
require_relative "async_variants/process_job"
require_relative "async_variants/heartbeat_watchdog_job"

module ActiveStorage
  module AsyncVariants
    # How long an external transform may go without a heartbeat before the
    # watchdog fails it. Must exceed the transformer's heartbeat interval.
    mattr_accessor :heartbeat_stale_after, default: 60.seconds

    # The transformer's heartbeat cadence. External services report at this
    # rate; the UI layer's turbo-frame poll matches it. Keep heartbeat_stale_after
    # well above it.
    mattr_accessor :heartbeat_interval, default: 5.seconds

    def self.configure
      yield self
    end

    class Engine < ::Rails::Engine
      # Prepend the core model/reflection extensions before eager_load runs
      # so that models' has_X_attached blocks (and the Variation.wrap calls
      # they trigger via reflection.variant) go through our hooks. The
      # :before_eager_load load_hook fires from the eager_load! initializer
      # in finisher_hook, after all autoload paths have been set up but
      # before any model class is loaded.
      # :nocov:
      ActiveSupport.on_load(:before_eager_load) do
        ActiveStorage::AsyncVariants.prepend_model_extensions!
      end
      # :nocov:

      config.after_initialize do
        # Idempotent — covers eager_load=false (dev/test) where the
        # :before_eager_load hook never fires. Models autoload lazily on
        # demand, and we just need the extensions in place by the time
        # the first one loads.
        ActiveStorage::AsyncVariants.prepend_model_extensions!
      end
    end

    def self.prepend_model_extensions!
      require "active_storage/reflection"
      ActiveStorage::Reflection::HasAttachedReflection.prepend(
        ActiveStorage::AsyncVariants::ReflectionExtension
      )
      ActiveStorage::Blob.prepend(
        ActiveStorage::AsyncVariants::BlobExtension
      )
      ActiveStorage::Variation.prepend(
        ActiveStorage::AsyncVariants::VariationExtension
      )
      ActiveStorage::VariantWithRecord.prepend(
        ActiveStorage::AsyncVariants::VariantWithRecordExtension
      )
      ActiveStorage::VariantRecord.include(
        ActiveStorage::AsyncVariants::VariantRecordExtension
      )
      ActiveStorage::Attachment.prepend(
        ActiveStorage::AsyncVariants::AttachmentExtension
      )
      ActiveStorage::Preview.prepend(
        ActiveStorage::AsyncVariants::PreviewExtension
      )
    end

    # Attaches a frame placeholder (byte_size 0, checksum "0") as the blob's
    # preview_image, mirroring stock's once-per-blob preview extraction. The
    # external transformer writes the real frame to it; the success callback
    # reconciles the sentinel metadata.
    def self.ensure_preview_image_placeholder!(blob)
      return blob.preview_image.blob if blob.preview_image.attached?

      frame = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "#{blob.filename.base}.jpg",
        content_type: "image/jpeg",
        metadata: { analyzed: true },
        service_name: blob.service_name,
        byte_size: 0,
        checksum: "0",
      )
      blob.preview_image.attach(frame)
      frame
    end

    def self.callback_token_for(variant_record)
      ActiveStorage.verifier.generate(variant_record.id, purpose: :async_variant_callback)
    end

    def self.callback_url_for(variant_record)
      url_options = ActiveStorage::Current.url_options || Rails.application.default_url_options
      token = callback_token_for(variant_record)
      Rails.application.routes.url_helpers.active_storage_async_variant_callback_url(
        token: token,
        **url_options,
      )
    end
  end
end
