Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false
  config.active_storage.service = :test
end
