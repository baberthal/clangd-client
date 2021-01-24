# frozen_string_literal: true

require "clangd_client/gem_version"

require "clangd_client/logging"
require "clangd_client/version"

# Top-level module for the clangd client.
module ClangdClient
  class Error < StandardError; end

  # Returns +true+ if ClangdClient is running on a Linux platform.
  #
  # @return [Boolean]
  def self.linux?
    /linux/i.match?(RUBY_PLATFORM)
  end

  # Returns +true+ if ClangdClient is running on a mac platform.
  #
  # @return [Boolean]
  def self.darwin?
    /darwin/i.match?(RUBY_PLATFORM)
  end

  # Returns +true+ if ClangdClient is running on a unix-like platform.
  #
  # @return [Boolean]
  def self.unix?
    linux? || darwin? ||
      /(aix|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i.match?(RUBY_PLATFORM)
  end
end
