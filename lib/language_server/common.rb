# frozen_string_literal: true

require "language_server/common/gem_version"
require "language_server/common/logging"
require "language_server/common/process_handle"
require "language_server/common/utils"

module LanguageServer
  # Common code for the language server library.
  module Common
  end
end

LS = LanguageServer unless defined?(LS)
