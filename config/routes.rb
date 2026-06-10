# frozen_string_literal: true

Rails.application.routes.draw do
  post "/active_storage/async_variants/callbacks/:token",
    to: "active_storage/async_variants/callbacks#create",
    as: :active_storage_async_variant_callback
end
