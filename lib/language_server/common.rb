# frozen_string_literal: true

require "language_server/common/gem_version"
require "language_server/common/logging"
require "language_server/common/thread_startable"

# Common code for the language server library.
module LanguageServer
end

LS = LanguageServer unless defined?(LS)
