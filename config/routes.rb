# frozen_string_literal: true

Rails.application.routes.draw do
  root 'home#index'

  resources :resques, only: %i[index show] do
    resource :jobs, only: [:show] do
      resources :failed, only: %i[index show destroy] do
        collection do
          post 'retry_all'
          delete 'clear_all'
        end
        member do
          post 'retry'
        end
      end
      member do
        get 'running'
        get 'waiting'
      end
    end
    resources :workers, only: [:destroy]
    resource :schedule, only: [:show] do
      post 'queue'
    end
  end
end
