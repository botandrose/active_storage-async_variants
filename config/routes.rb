# frozen_string_literal: true

Rails.application.routes.draw do
  post "/active_storage/async_variants/callbacks/:token",
    to: "active_storage/async_variants/callbacks#create",
    as: :active_storage_async_variant_callback

  get  "/active_storage/async_variants/states/:signed_blob_id/:variation_key",
    to: "active_storage/async_variants/states#show",
    as: :async_variant_state
  post "/active_storage/async_variants/states/:signed_blob_id/:variation_key/retry",
    to: "active_storage/async_variants/states#retry",
    as: :async_variant_state_retry

  ActiveStorage::AsyncVariants::Assets.draw(self, "/active_storage/async_variants/assets")
end
