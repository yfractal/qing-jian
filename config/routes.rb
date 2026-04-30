Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "remember_words#index"
  get "today_words", to: "remember_words#today", as: :today_words
  get "words/statistics", to: "remember_words#statistics", as: :statistics_words

  resources :words do
    collection do
      post :lookup
      post :batch_lookup
      post :batch_create
    end
  end
  resources :word_question_records, only: :create
end
