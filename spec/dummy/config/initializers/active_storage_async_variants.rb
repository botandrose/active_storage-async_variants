Rails.application.config.to_prepare do
  ActiveStorage::AsyncVariants.parent_controller = "ApplicationController"
end
