# frozen_string_literal: true

require_relative "version"
require_relative "logging"

module ClangdClient
  # Represents the command that will be run for clangd.
  class ClangdCommand
    extend Logging

    MIN_SUPPORTED_VERSION = Version.new(11, 0, 0)
    NOT_CACHED = Object.new.freeze
    @clangd_command = NOT_CACHED

    def self.get(user_options)
      if @clangd_command != NOT_CACHED
        log_info "Returning cached clangd command: #{@clangd_command}"
        return @clangd_command
      end

      @clangd_command = nil

      installed_clangd, resource_dir = get_clangd_exe_and_resource_dir(
        user_options
      )
      return nil unless installed_clangd

      @clangd_command = build_clangd_command(installed_clangd,
                                             resource_dir,
                                             user_options)
      @clangd_command
    end

    # Return the Clangd binary from the pathc specified in the
    # 'clangd_binary_path' user option. Let the binary find its own resource
    # directory in that case. If no binary is found or if it's out-of-date,
    # return nil. If 'clangd_binary_path' is empty, return the third-party
    # bundled clangd and its resource directory if the user downloaded it and
    # it's up to date. Otherwise, return nothing.
    def self.get_clangd_exe_and_resource_dir(user_options)
      clangd = user_options["clangd_binary_path"]
      resource_dir = nil

      if clangd && !clangd.empty?
        clangd = Utils.find_executable(Utils.expand_variables_in_path(clangd))

        unless clangd
          log_error "No clangd executable found at #{user_options['clangd_binary_path']}"
          return nil, nil
        end

        check_clangd_version(clangd) do
          log_error "Clangd at #{clangd} is out-of-date"
          return nil, nil
        end
        # Try to look for the pre-built binary
      else
        return nil, nil unless third_party_clangd

        clangd = third_party_clangd
        resource_dir = CLANG_RESOURCE_DIR
      end

      log_info "Using clangd from #{clangd}"
      [clangd, resource_dir]
    end

    def self.third_party_clangd
      @third_party_clangd ||= find_third_party_clangd
    end

    def self.find_third_party_clangd; end

    def self.check_clangd_version(clangd_path)
      version = Version.get(clangd_path)
      ok = if version && version < MIN_SUPPORTED_VERSION
        false
      else
        true
      end

      yield if block_given? && !ok

      ok
    end

    def self.build_clangd_command(...)
      new(...).command
    end

    attr_reader :command, :resource_dir, :user_options

    def initialize(installed_clangd, resource_dir, user_options)
      @resource_dir = resource_dir
      @user_options = user_options

      @command = [installed_clangd]
      build_command!
    end

    def build_command!
      clangd_args = @user_options["clangd_args"]
      put_resource_dir = false
      put_limit_results = false
      put_header_insertion_decorators = false
      put_log = false

      clangd_args.each do |arg|
        @command.push(arg)
        put_resource_dir ||= arg.start_with?("-resource-dir")
        put_limit_results ||= arg.start_with?("-limit-results")
        put_header_insertion_decorators ||= arg.start_with?("-header-insertion-decorators")
        put_log ||= arg.start_with?("-log")

        unless put_header_insertion_decorators
          @command.push("-header-insertion-decorators")
        end
        if resource_dir && !put_resource_dir
          @command.push("-resource-dir=#{resource_dir}")
        end
        if user_options["clangd_uses_caching"] && !put_limit_results
          @command.push("-limit-results=500")
        end
        if Logging.enabled_for?(::Logger::DEBUG) && !put_log
          @command.push("-log=verbose")
        end
      end

      @command
    end
  end
end
