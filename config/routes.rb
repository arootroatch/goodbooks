Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resource :theme, only: :update
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
    resource :tithe, only: %i[show update], controller: "tithes"
    resources :accounts, only: %i[index new create edit update] do
      resources :csv_imports, only: %i[new create show destroy] do
        post :commit, on: :member
        resource :mapping, only: %i[edit update], controller: "csv_import_mappings"
      end
    end
    resources :categories, only: %i[index new create edit update]
    resources :clients, only: %i[index new create edit update]
    resources :invoices do
      member do
        patch :mark_sent
        patch :void
        patch :reopen
      end
      resource :pdf, only: :show, controller: "invoice_pdfs"
      resources :payments, only: %i[new create destroy], controller: "invoice_payments"
    end
    resources :transactions, except: :show do
      resource :classification, only: :update
    end
    resources :rules, except: :show do
      patch :move, on: :member
      post :apply, on: :collection
    end
    resources :mileage_entries, except: :show
    resources :memberships, only: %i[index update destroy]
    resource :inbox, only: :show
    get "reports/profit_and_loss", to: "profit_and_losses#show", as: :profit_and_loss
    get "reports/schedule_c", to: "schedule_cs#show", as: :schedule_c
    get "reports/mileage_log", to: "mileage_logs#show", as: :mileage_log
    get "reports/transactions", to: "transaction_exports#show", as: :transaction_export
    get "reports/aging", to: "invoice_agings#show", as: :invoice_aging
    get "reports/spending", to: "spending_reports#show", as: :spending_report
  end

  resources :tax_parameters, only: %i[index new create edit update]

  resources :invites, only: %i[index new create destroy]
  get "join", to: "invite_acceptances#show", as: :join
  post "join", to: "invite_acceptances#create"
  resources :people, only: %i[index new create edit update]
  resource :personal_book, only: :create

  get "inbox", to: "household_inboxes#show", as: :household_inbox

  scope "household", as: "household" do
    get "profit_and_loss", to: "household_profit_and_losses#show", as: :profit_and_loss
    get "transactions", to: "household_transaction_exports#show", as: :transaction_export
    get "invoices", to: "household_invoices#show", as: :invoices
    get "aging", to: "household_invoice_agings#show", as: :invoice_aging
  end

  root "dashboards#show"
end
