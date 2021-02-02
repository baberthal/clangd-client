# frozen_string_literal: true

module LanguageServer
  # Represents a child process.
  class ProcessHandle
    # Opaque constant to signify the stream is going through a pipe.
    PIPE = Object.new.freeze

    # Opaque constant to signify the stream is being redirected to STDOUT.
    STDOUT = Object.new.freeze

    # The IO that is connected to the process's `stdin`.
    #
    # @return [IO]
    attr_reader :stdin

    # The IO that is connected to the process's `stdout`.
    #
    # @return [IO]
    attr_reader :stdout

    # The IO that is connected to the process's `stderr`.
    #
    # @return [IO]
    attr_reader :stderr

    # Any environment variables that should be set in the child process.
    #
    # @return [Hash<String => String>]
    attr_reader :env

    # The command that this process was invoked with.
    #
    # @return [Array<String>]
    attr_reader :command

    alias args command

    # The process ID of the spawned process.
    #
    # @return [Integer]
    attr_reader :pid

    # The exit status object for the process. Only set after the process has
    # exited.
    #
    # @return [::Process::Status]
    attr_reader :status

    # Creates a new process handle.
    #
    # @param command [Array<String>] Command with which to spawn the process.
    # @param options [Hash] Options hash
    #
    # @option options [ProcessHandle::PIPE, IO] :stdin
    #   standard input for the process.
    # @option options [ProcessHandle::PIPE, IO] :stdout
    #   standard output for the process.
    # @option options [ProcessHandle::PIPE, IO] :stderr
    #   standard error for the process.
    # @option options [Hash{String => String,nil}] :env
    #   environment variables for the process.
    def initialize(command, **options, &block)
      @command = command
      @options = options
      @env     = options.delete(:env)

      # Figure out what file descriptors we should pass to the child, and which
      # we should make externally visible.
      @child_stdin,  @stdin  = parse_fd_options(options[:stdin], "r")
      @child_stdout, @stdout = parse_fd_options(options[:stdout], "w")
      @stdin.sync = true if options[:stdin] == ProcessHandle::PIPE

      unless stderr_to_stdout?
        @child_stderr, @stderr = parse_fd_options(options[:stderr], "w")
      end

      run_process(&block)
    end

    def spawn_options
      @spawn_options ||= begin
        opts = options.except(:stdin, :stdout, :stderr)
        opts[:in] = @child_stdin if @child_stdin

        if stderr_to_stdout?
          opts[%i[out err]] = @child_stdout if @child_stdout
        else
          opts[:out] = @child_stdout if @child_stdout
          opts[:err] = @child_stderr if @child_stderr
        end

        opts
      end
    end

    # Poll the child, setting (and returning) its status. If the child has not
    # terminated, return nil and exit immediately.
    #
    # @return [::Process::Status, nil] The exit status of the process.
    def poll
      @status ||= (::Process.waitpid2(@pid, ::Process::WNOHANG) || []).last
    end

    # Wait for the child to return, setting and returning the status of the
    # child.
    #
    # @return [::Process::Status] The exit status of the process.
    def wait
      @status ||= ::Process.waitpid2(@pid).last
    end

  protected

    attr_reader :options

  private

    def run_process
      # Ruby's Kernel#spawn will call an exec(3) variant if called with two
      # or more arguments, but when called with just a single argument
      # will spawn a subshell with that argument as the command. Since we
      # always want to call exec(3), we use the third exec form, which
      # passes a [cmdname, argv0] array as its first argument and never
      # invokes a subshell.
      @pid = spawn([command[0], command[0]], *command[1..], spawn_options)
      @child_stdin.close if need_to_close_fd?(options[:stdin])
      @child_stdout.close if need_to_close_fd?(options[:stdout])
      @child_stderr.close if need_to_close_fd?(options[:stderr])

      if block_given?
        begin
          return yield(self)
        ensure
          [@stdin, @stdout, @stderr].compact.each(&:close)
          Process.detach(@pid).join
        end
      end

      self
    end

    def stderr_to_stdout?
      options[:stderr] == ProcessHandle::STDOUT
    end

    # Return a pair of values (child, mine), which are how the given file
    # descriptor should appear to the child and to this process, respectively.
    # "mine" is only non-nil in the case of a pipe (in fact, we just return an
    # array of length one, since ruby will unpack nils from missing array items).
    def parse_fd_options(fd, mode)
      fds = case fd
      when PIPE
        IO.pipe
      when IO
        [fd]
      when Integer
        [IO.new(fd, mode)]
      when String
        [File.open(fd, mode)]
      when nil
        []
      else
        raise ArgumentError
      end

      mode == "r" ? fds : fds.reverse
    end

    def need_to_close_fd?(fd)
      case fd
      when ProcessHandle::PIPE, String then true
      else false
      end
    end
  end
end
