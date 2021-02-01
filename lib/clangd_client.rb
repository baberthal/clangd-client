# frozen_string_literal: true

require "language_server/common"

require "clangd_client/gem_version"

require "clangd_client/clangd_command"
require "clangd_client/user_options"
require "clangd_client/utils"
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

  # Returns +true+ if ClangdClient is running on a unix-like platform other than
  # darwin or linux.
  #
  # @return [Boolean]
  def self.other_unix?
    /(aix|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i.match?(RUBY_PLATFORM)
  end

  # Returns +true+ if ClangdClient is running on a unix-like platform.
  #
  # @return [Boolean]
  def self.unix?
    linux? || darwin? || other_unix?
  end

  # Returns +true+ if ClangdClient is running on a windows platform.
  #
  # @return [Boolean]
  def self.windows?
    !unix?
  end
end
