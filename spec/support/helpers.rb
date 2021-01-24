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
      ret = nil
      t = Tempfile.new("vim-channel-tests")

      begin
        old_stdout = $stdout.dup
        $stdout.reopen(t)
        $stdout.sync = true
        yield
        t.rewind
        ret = t.read
      ensure
        $stdout.reopen(old_stdout)
        t.close
      end
      ret
    end
  end
end
