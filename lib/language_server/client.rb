# frozen_string_literal: true

require "concurrent"

require "language_server/client/gem_version"

module LanguageServer
  # Module for LanguageServer Client-related code.
  module Client
  end
end

LS = LanguageServer unless defined?(LS)
