begin
  require 'sidekiq/web'
rescue LoadError
  # Sidekiq not available, skip web interface
end

Rails.application.routes.draw do
  # Devise routes with custom controllers
  devise_for :users, controllers: {
    registrations: 'users/registrations',
    sessions: 'users/sessions'
  }, path: '', path_names: {
    sign_in: 'login',
    sign_out: 'logout',
    sign_up: 'register'
  }

  # Unauthenticated root for guests
  devise_scope :user do
    unauthenticated do
      root 'devise/sessions#new', as: :unauthenticated_root
    end
  end

  # Health check endpoints
  get '/health', to: 'health#index'
  get '/health/dashboard', to: 'health#dashboard'
  get "up" => "rails/health#show", as: :rails_health_check

  # Admin namespace
  namespace :admin do
    root to: 'admin#index', as: :dashboard

    # Sidekiq web interface for job monitoring (if available)
    if defined?(Sidekiq::Web)
      mount Sidekiq::Web => '/sidekiq'
    end
    resources :users
    resources :courses do
      member do
        get 'students'  # For viewing students
        post 'add_students'  # For adding multiple students
      end
    end
    get '/system', to: 'admin#system', defaults: { format: :html }
    get '/system', to: 'admin#system', defaults: { format: :json }
    get '/metrics', to: 'metrics#index'
    post '/metrics/health_check', to: 'metrics#health_check'
    post '/cleanup', to: 'admin#cleanup_data'
    post '/clear_cache', to: 'admin#clear_cache'
    post '/cleanup_logs', to: 'admin#cleanup_logs'
    get '/download_logs', to: 'admin#download_logs'

    # User management actions
    scope '/users' do
      post '/:id/lock', to: 'admin#lock_user', as: :lock_user
      post '/:id/unlock', to: 'admin#unlock_user', as: :unlock_user
    end
  end

  # Authenticated routes - note the routing based on user role
  authenticate :user do
    constraints lambda { |request|
      user = request.env['warden'].user
      user = User.find_by(id: user.first.first) if user.is_a?(Array)
      user&.admin?
    } do
      root to: 'admin/admin#index', as: :admin_root
    end

    constraints lambda { |request|
      user = request.env['warden'].user
      user = User.find_by(id: user.first.first) if user.is_a?(Array)
      !user&.admin?
    } do
      root to: 'dashboard#show'
    end

    get '/dashboard', to: 'dashboard#show', as: :dashboard

    resources :courses do
      member do
        post 'add_student'
        delete 'remove_student'
        patch 'update_grade'
        get 'stats'
      end
    end

    resources :performance_metrics, only: [:index]

    # Teaching metrics for teachers
    resources :teaching_metrics, only: [:index], controller: 'teaching_metrics'
  end
end
