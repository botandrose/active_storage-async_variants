Rails.application.routes.draw do
  get "/session/:user_id", to: "sessions#show", as: :session
  delete "/session",       to: "sessions#destroy"
  get "/avatars/:user_id/:variant_name", to: "avatars#show", as: :avatar
end
