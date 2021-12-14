Rails.application.routes.draw do
  resources :events

  root "hellos#index"

  get "/hellos", to: "hellos#index"
end
