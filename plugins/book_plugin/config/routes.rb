BookPlugin::Engine.routes.draw do
  resources :books do
    resources :flash_cards, only: [:index, :new, :create, :edit, :update, :destroy]
  end

  root to: "books#index"
end
