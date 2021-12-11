Rails.application.routes.draw do
  root "hellos#index"

  get "/hellos", to: "hellos#index"
end
