# frozen_string_literal: true

require "language_server/common/logging"

module ClangdClient
  # General utility methods that have no other home.
  module Utils
    CLANG_RESOURCE_DIR = ""

  module_function

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
      if File.dirname(executable) != "." && executable.include?(File::SEPARATOR)
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

    def root_directory?(path, parent)
      path == parent
    end

    def paths_to_all_parent_folders(path)
      folder = File.expand_path(path)

      yield folder if File.directory?(folder)

      loop do
        parent = File.dirname(folder)
        break if root_directory?(folder, parent)

        folder = parent
        yield folder
      end
    end

    def list_directory(path)
      Dir.foreach(path).reject { |p| %w[. ..].include?(p) }
    rescue StandardError => e
      LanguageServer::Logging.log_error("Error while listing #{path} folder", e)
      []
    end

    def _get_clang_resource_dir
      resource_dir = File.join(LIBCLANG_DIR, "clang")

      list_directory(resource_dir).each do |version|
        return File.join(resource_dir, version)
      end

      raise "Cannot find Clang resource directory."
    end
  end
end
