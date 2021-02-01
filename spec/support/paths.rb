# frozen_string_literal: true

require "pathname"

module Spec
  module Paths
  module_function

    # Returns the path to the root directory of the repository.
    #
    # @return [Pathname]
    def root
      @root ||= Pathname.new("../../..").expand_path(__FILE__)
    end

    # Returns the path to the root spec directory.
    #
    # @return [Pathname]
    def spec_dir
      @spec_dir ||= root.join("spec")
    end

    # Returns the path to spec/fixtures.
    #
    # @return [Pathname]
    def fixtures_dir
      @fixtures_dir ||= spec_dir.join("fixtures")
    end

    # Returns the path to a specified fixture.
    #
    # @param path [String] Path to the desired fixture, relative from
    # spec/fixtures.
    #
    # @return [Pathname]
    def fixture(*path)
      fixtures_dir.join(*path)
    end

    # Returns a path to a temporary directory, depending on the scope of the
    # test.
    #
    # @return [Pathname]
    def tmp(*path)
      root.join("tmp", scope, *path)
    end

    # Returns the scope of the test (i.e. TEST_ENV_NUMBER if it's set, or "1")
    def scope
      test_number = ENV["TEST_ENV_NUMBER"]
      return "1" if test_number.nil?

      test_number.empty? ? "1" : test_number
    end
  end
end
