Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resource :two_factor, only: %i[new create]
  resource :two_factor_setup, only: %i[new create]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  resource :setup, only: %i[new create]

  resources :businesses, only: %i[new create show edit update] do
    resources :accounts, only: %i[index new create edit update]
    resources :categories, only: %i[index new create edit update]
    resources :transactions, except: :show
    resources :rules, except: :show do
      patch :move, on: :member
      post :apply, on: :collection
    end
    resource :inbox, only: :show
  end

  root "dashboards#show"
end
