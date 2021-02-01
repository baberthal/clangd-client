# frozen_string_literal: true

require "concurrent"

require "language_server/client/gem_version"
require "language_server/client/base"
require "language_server/client/errors"
require "language_server/client/language_server_connection"
require "language_server/client/response"

module LanguageServer
  # Module for LanguageServer Client-related code.
  module Client
  end
end

LS = LanguageServer unless defined?(LS)
