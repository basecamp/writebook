source "https://rubygems.org"

ruby file: ".ruby-version"

gem "rails", github: "rails/rails"

# Drivers
gem "sqlite3", "~> 2.5"
gem "activerecord-tenanted", github: "basecamp/activerecord-tenanted"
gem "redis", ">= 4.0.1"

# Deployment
gem "puma", ">= 5.0"

# Jobs
gem "resque", "~> 2.6.0"
gem "resque-pool", "~> 0.7.1"

# Front-end
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"

# Other
gem "jbuilder"
gem "redcarpet", "~> 3.6"
gem "rouge", "~> 4.5"
gem "bcrypt", "~> 3.1.7"
gem "image_processing", "~> 1.13"
gem "rqrcode"
gem "thruster"
gem "useragent", github: "basecamp/useragent"
gem "front_matter_parser"

group :development, :test do
  gem "debug"
  gem "faker", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
