source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# Use Sprockets for the asset pipeline
gem "sprockets-rails"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Add devise for authentication
gem "devise"

# Add redis for caching
gem "redis", "~> 5.0"
gem "redis-namespace"
gem "redis-rack-cache"

# Background job processing with SolidQueue
gem "solid_queue"
gem "rufus-scheduler", '~> 3.9'

# Add rack-attack for rate limiting
gem "rack-attack"

# Add lograge for better logging
gem "lograge"

# Add terser for JS compression
gem "terser"
gem "sass-rails"

# Add dotenv for environment variables
gem "dotenv-rails"

# Add bootstrap for styling
gem "bootstrap", "~> 5.3.0"
gem "sassc-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Monitoring and metrics
gem 'prometheus-client'
gem 'rack-timeout'

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mingw x64_mingw ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Testing and debugging tools
  gem 'capybara', '~> 3.39'
  gem 'selenium-webdriver', '~> 4.10'
  gem 'webdrivers', '~> 5.3'

  gem 'terminal-table', require: false  # Pretty command line tables
  gem 'rainbow', require: false         # Colorized terminal output

  gem 'faker'
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Add bullet for N+1 query detection
  gem "bullet"
  
  # Add dev debugging tools
  gem "better_errors"
  gem "binding_of_caller"
  gem "pry-rails"
  gem 'launchy'  # For opening URLs
end

gem "foreman", "~> 0.88.1"
