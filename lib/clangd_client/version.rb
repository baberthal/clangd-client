# frozen_string_literal: true

require "subprocess"

module ClangdClient
  # Simple class to parse and store the version of clangd we are running.
  class Version
    VERSION_REGEXP = /(\d+)\.(\d+)\.(\d+)/.freeze

    include Comparable

    # Parse a version from a string, e.g. "11.0.0"
    #
    # @param version_str [String] String to parse version info from.
    #
    # @return [Version]
    def self.parse(version_str)
      VERSION_REGEXP.match(version_str) do |m|
        new(m[1].to_i, m[2].to_i, m[3].to_i)
      end
    end

    # Get the version of the clangd binary at +path+.
    #
    # @param clangd_path [String] Path to the clangd binary
    #
    # @return [Version]
    def self.get(clangd_path)
      args = [clangd_path, "--version"]
      stdout, = Subprocess.popen(args, stdout: Subprocess::PIPE).communicate
      parse(stdout)
    end

    # Major version of the clangd binary
    # @return [Integer]
    attr_reader :major

    # Minor version of the clangd binary
    # @return [Integer]
    attr_reader :minor

    # Patch version of the clangd binary
    # @return [Integer]
    attr_reader :patch

    def initialize(major, minor, patch)
      @major = major
      @minor = minor
      @patch = patch
    end

    def [](idx)
      to_a[idx]
    end

    def to_s
      to_a.join(".")
    end

    def to_a
      [major, minor, patch]
    end

    def <=>(other)
      major_cmp = major <=> other.major
      return major_cmp if major_cmp.nonzero?

      minor_cmp = minor <=> other.minor
      return minor_cmp if minor_cmp.nonzero?

      patch <=> other.patch
    end
  end
end
