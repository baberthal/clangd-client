# frozen_string_literal: true

require "language_server/client/language_server_connection"

module LanguageServer
  module Client
    # Concrete language server connection that uses stdin/stdout to communicate
    # with the server. This should be the default choice for concrete client
    # implementations.
    class StandardIOLanguageServerConnection < LanguageServerConnection
      def initialize(project_directory, server_stdin, server_stdout, ...)
        super(project_directory, ...)

        @server_stdin  = server_stdin
        @server_stdout = server_stdout

        @stdin_lock  = Mutex.new
        @stdout_lock = Mutex.new
      end

      def try_server_connection_blocking
        true
      end

      def connected?
        # TODO: (maybe) @server_stdin.closed? / @server_stdout.closed?
        true
      end

      def shutdown
        super

        @stdin_lock.synchronize do
          @server_stdin.close unless @server_stdin.closed?
        end

        @stdout_lock.synchronize do
          @server_stdout.close unless @server_stdout.closed?
        end
      end

      def write_data(data)
        @stdin_lock.synchronize do
          @server_stdin.write(data)
          @server_stdin.flush
        end
      end

      def read_data(size = -1)
        data = nil
        @stdout_lock.synchronize do
          unless @server_stdout.closed?
            data = if size > -1
              @server_stdout.read(size)
            else
              @server_stdout.readline
            end
          end
        end

        unless data
          # No data means the connection was closed. Connection closed when (not
          # stopped?) means the server died unexpectedly.
          raise LanguageServerConnectionStopped if stopped?

          raise "Connection to server died."
        end

        data
      end
    end
  end
end
