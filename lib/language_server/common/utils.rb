# frozen_string_literal: true

require "tempfile"
require "language_server/common/process_handle"

module LanguageServer
  # General utility methods with no other home.
  module Utils
  module_function

    # Returns a file object that can be used to replace $stdout or $stderr
    def open_for_std_handle(filepath, &block)
      File.open(filepath, "w", &block)
    end

    # Return a representation of +s+ that is safe for use in a file name.
    # Explicitly, return +s+ converted to lowercase with all non alphanumeric
    # characters replaced with '_'.
    #
    # @param str [String]
    #
    # @return [String]
    def safe_filename_string(str)
      is_ascii_alnum = ->(c) { /[[:alnum:]]/.match?(c) && c.ord < 128 }

      str.downcase.each_char.map { |c| is_ascii_alnum[c] ? c : "_" }.join
    end

    def create_logfile(prefix = "")
      Tempfile.new([prefix, ".log"]).path
    end

    def path_to_first_existing_executable(names)
      names.each do |name|
        path = find_executable(name)
        return path if path
      end

      nil
    end

    def get_executable(filename)
      return filename if File.file?(filename) && File.executable?(filename)
    end

    def find_executable(executable)
      # If we're given a path with a directory part, look it up rather than
      # referring to the directories in $PATH. This includes checking relative
      # to the current directory, i.e. ./script
      if File.dirname(executable) != "." || executable.include?(File::SEPARATOR)
        return get_executable(executable)
      end

      paths = ENV["PATH"].split(File::PATH_SEPARATOR)

      paths.each do |path|
        exe = get_executable(File.join(path, executable))
        return exe if exe
      end

      nil
    end

    def expand_variables_in_path(path)
      File.expand_path(path)
    end

    def remove_dir_if_exists(dirname)
      FileUtils.rmtree(dirname)
    end

    def remove_if_exists(filepath)
      File.delete(filepath)
    rescue Errno::ENOENT
      nil
    end

    def popen(...)
      ProcessHandle.new(...)
    end

    def process_running?(handle)
      !handle.nil? && handle.poll.nil?
    end

    def wait_for_process_to_terminate(handle, timeout: 5)
      expiration = Time.now + timeout
      loop do
        if Time.now > expiration
          raise "Waited #{timeout} seconds for process to terminate, aborting"
        end

        return unless process_running?(handle)

        sleep(0.1)
      end
    end
  end
end
