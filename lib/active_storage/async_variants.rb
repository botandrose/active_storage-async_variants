# frozen_string_literal: true

require "turbo-rails"
require_relative "async_variants/version"
require_relative "async_variants/helper"
require_relative "async_variants/transformer"
require_relative "async_variants/registry"
require_relative "async_variants/blob_extension"
require_relative "async_variants/variation_extension"
require_relative "async_variants/variant_with_record_extension"
require_relative "async_variants/variant_record_extension"
require_relative "async_variants/preview_extension"
require_relative "async_variants/attachment_extension"
require_relative "async_variants/reflection_extension"
require_relative "async_variants/process_job"
require_relative "async_variants/asset_tag_helper_extension"

module ActiveStorage
  module AsyncVariants
    # HTML attributes round-tripped through the state-endpoint URL so the
    # eventual processed-state render can apply them to the inner <img>/<video>.
    PASS_THROUGH_HTML_OPTIONS = %i[alt width height controls autoplay preload].freeze

    mattr_accessor :cdn_host

    # Lets the host app plug its auth chain (and thus `current_user`) into the
    # gem's StatesController. Set to a string so resolution is deferred until
    # the host's class is autoloadable. Defaults to ActionController::Base.
    mattr_accessor :parent_controller, default: "ActionController::Base"

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

        ActionView::Helpers::AssetTagHelper.prepend(
          ActiveStorage::AsyncVariants::AssetTagHelperExtension
        )
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
