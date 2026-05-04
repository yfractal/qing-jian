BookPlugin::Engine.routes.draw do
  get "flash_cards/remember", to: "flash_card_remember#index", as: :remember_flash_cards
  resources :flash_card_recall_records, only: [:create]

  resources :books do
    resources :flash_cards, only: [:index, :new, :create, :edit, :update, :destroy]
  end

  root to: "books#index"
end
