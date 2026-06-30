Rails.application.routes.draw do
  root "books#index"

  resource :first_run, only: %i[ show create ]

  resource :session, only: %i[ new create destroy ] do
    scope module: "sessions" do
      resources :transfers, only: %i[ show update ]
    end
  end

  get "join/:join_code", to: "users#new", as: :join
  post "join/:join_code", to: "users#create"

  resource :account do
    scope module: "accounts" do
      resource :join_code, only: :create
      resource :custom_styles, only: %i[ edit update ]
    end
  end

  resources :books, except: %i[ index show ] do
    resource :publication, controller: "books/publications", only: %i[ show edit update ]
    resource :bookmark, controller: "books/bookmarks", only: :show

    scope module: "books" do
      namespace :leaves do
        resources :moves, only: :create
      end

      resource :search
    end

    resources :sections
    resources :pictures
    resources :pages
  end

  # PDF page size via suffix: `.pdf` defaults to Letter; `.A4.pdf`/`.letter.pdf` force a size.
  get "/:id/:slug.:size.pdf", to: "books#show", constraints: { id: /\d+/, size: /A4|letter/i },
    format: false, defaults: { format: "pdf" }, as: :sized_book_pdf
  get "/:id/:slug", to: "books#show", constraints: { id: /\d+/ }, as: :slugged_book
  get "/:book_id/:book_slug/:id/:slug", to: "leafables#show", constraints: { book_id: /\d+/, id: /\d+/ }, as: :slugged_leafable

  direct :book_slug do |book, options|
    route_for :slugged_book, book, book.slug, options
  end

  direct :leafable_slug do |leaf, options|
    route_for :slugged_leafable, leaf.book, leaf.book.slug, leaf, leaf.slug, options
  end

  resources :pages, only: [] do
    scope module: "pages" do
      resources :edits, only: :show
    end
  end

  resources :qr_code, only: :show
  resources :users do
    scope module: "users" do
      resource :profile
    end
  end

  direct :leafable do |leaf, options|
    route_for "book_#{leaf.leafable_name}", leaf.book, leaf, options
  end

  direct :edit_leafable do |leaf, options|
    route_for "edit_book_#{leaf.leafable_name}", leaf.book, leaf, options
  end

  namespace :action_text, path: nil do
    get "/u/*slug" => "markdown/uploads#show", as: :markdown_upload
    post "/uploads" => "markdown/uploads#create", as: :markdown_uploads
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
