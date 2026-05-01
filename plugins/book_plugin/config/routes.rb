BookPlugin::Engine.routes.draw do
  resources :books do
    resources :flash_cards, only: [:new, :create]
  end

  root to: "books#index"
end
