BookPlugin::Engine.routes.draw do
  resources :books do
    resources :flash_cards, only: [:index, :new, :create, :edit, :update, :destroy]
    get "flash_cards/remember", to: "flash_card_remember#index", as: :remember_book_flash_cards
    resources :flash_card_recall_records, only: [:create]
  end

  root to: "books#index"
end
