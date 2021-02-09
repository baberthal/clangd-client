# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in clangd_client.gemspec
gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"

gem "concurrent-ruby"
gem "concurrent-ruby-ext", platform: :mri

gem "listen"

gem "async-io"

gem "abc", path: "../abc"

gem "subprocess"

group :development, :test do
  # Use the new static analysis system
  gem "rbs"

  # Use rubocop
  gem "rubocop"
  gem "rubocop-rake"
  gem "rubocop-rspec"

  # Use guard to run tests automatically
  gem "guard"
  gem "guard-rspec"

  # Runtime console and debugger
  gem "colorize"
  gem "pry"
  gem "pry-byebug"

  # Use simplecov for code coverage statistics
  gem "simplecov", require: false

  # Use solargraph as a language server for tooling in vim (via YCM)
  gem "solargraph"

  # Use yard for documentation generation
  gem "yard"
end
