# frozen_string_literal: true

require "tempfile"

module Spec
  module Helpers
    # Silences any stream for the duration of the block.
    #
    #   silence_stream($stdout) do
    #     puts "this will never be seen"
    #   end
    #
    #   puts "but this will"
    #
    # (Taken from ActiveSupport and Thin)
    def silence_stream(stream)
      old_stream = stream.dup
      # TODO: make this play nice on windows
      stream.reopen("/dev/null")
      stream.sync = true
      yield
    ensure
      stream.reopen(old_stream)
    end

    def silence_warnings
      old_verbose, $VERBOSE = $VERBOSE, nil
      yield
    ensure
      $VERBOSE = old_verbose
    end

    # Yield to the provided block, redirecting its STDOUT
    # temporarily, and return its output to our caller
    #
    #   msgs = with_redirected_stdout do
    #     server.do_something_that_logs
    #   end
    #
    #   puts msgs
    #
    def with_redirected_stdout
      return_value = nil
      fake_stdout = Tempfile.new("language-server-test-io")

      begin
        old_stdout = $stdout.dup
        $stdout.reopen(fake_stdout)
        $stdout.sync = true
        yield
        $stdout.fsync
        fake_stdout.rewind
        return_value = fake_stdout.read
      ensure
        $stdout.reopen(old_stdout)
        fake_stdout.close
      end
      return_value
    end

    def temporary_executable(extension = ".exe")
      Tempfile.open(["Temp", extension]) do |executable|
        executable.chmod(0o0100) # S_IXUSR
        yield executable.path
      end
    end
  end
end
