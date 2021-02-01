# frozen_string_literal: true

module LanguageServer
  module Client
    # Base class for LanguageServer clients.
    #
    # TODO: Document more.
    class Base
      include Logging

      # Number of seconds to block before returning true in poll_for_messages
      MESSAGE_POLL_TIMEOUT = 10

      # User-supplied options for the client.
      # @return [ClangdClient::UserOptions]
      attr_reader :user_options

      # Method that can be implemented by derived classes to return an instance
      # of {LanguageServerConnection} appropriate for the language server in
      # question.
      #
      # @return [LanguageServerConnection]
      attr_reader :connection

      # Creates a new instance of LanguageServer::Client::Base
      #
      # @param user_options [ClangdClient::UserOptions]
      def initialize(user_options, connection_type = :stdio)
        @user_options = user_options
        @connection_type = connection_type
        @semantic_tokens_cache = SemanticTokensCache.new

        # server_info_mutex synchronizes access to the state of the
        # LanguageServerClientBase object. There are a number of threads at play
        # here which might want to change properties of this object:
        #
        #  - Each client request (handled by concrete implementations) executes
        #    in a separate thread and might call methods requiring us to
        #    synchronize the server's view of file state with our own. We
        #    prevent clobbering by doing all server-file-state operations under
        #    this mutex.
        #
        #  - There are certain events that we handle in the message pump thread,
        #    like some parts of initialization. We must protect against
        #    concurrent access to our internal state (such as the server file
        #    state, and stored data about the server itself) when we are calling
        #    methods on this object from the message pump. We synchronize on
        #    this mutex for that.
        #
        #  - We need to make sure that multiple client requests don't try to
        #    start or stop ther server simultaneously, so we also do all server
        #    start/stop/etc. operations under this mutex.
        #
        #  - Acquiring this mutex from the poll thread can lead to deadlocks.
        #    Currently, this is avoided because we don't have any resources that
        #    are shared with that thread.
        @server_info_mutex = Mutex.new
        server_reset

        @on_file_ready_to_parse_handlers = []
        register_on_file_ready_to_parse do |request_data|
          _update_server_with_file_contents(request_data)
        end

        @server_keep_logfiles = user_options["server_keep_logfiles"]
        @stdout_file = nil
        @stderr_file = nil
        @server_started = false

        _reset
      end

      # Name of the client.
      #
      # @return [String]
      def client_name
        @client_name ||= self.class.name.sub(/Client/, "")
      end

      # Language supported by this client.
      #
      # @return [String]
      def language
        @language ||= @client_name.lower
      end

      def _reset
        server_reset
        @connection = nil
        @server_handle = nil

        if !@server_keep_logfiles && @stdout_file
          # TODO: Utils.remove_if_exists(@stdout_file)
          @stdout_file = nil
        end

        if !@server_keep_logfiles && @stderr_file
          # TODO: Utils.remove_if_exists(@stderr_file)
          @stderr_file = nil
        end

        true
      end

      # Clean up internal state related to the running server instance.
      # Implementations are required to call this after disconnection and
      # killing the downstream server.
      def server_reset
        @server_file_state = LS::Protocol::ServerFileStateStore.new
        @sync_type = full
        @initialize_response = nil
        @initialize_event = Concurrent::Event.new
        @on_initialize_complete_handlers = []
        @server_capabilities = nil
        @project_directory = nil
        @settings = {}
        @extra_conf_dir = nil
      end

      def start_server(request_data)
        @server_info_mutex.synchronize { _start_server_no_lock(request_data) }
      rescue LanguageServerConnectionTimeout
        log_error "#{server_name} failed to start, or did connect successfully."
        shutdown
        false
      end

      def _start_server_no_lock(request_data)
        log_info "Starting #{server_name}:#{command_line}"

        @project_directory = get_project_directory(request_data)

        raise "TCP Currently unsupported" if @connection_type == :tcp

        @stderr_file = Utils.create_logfile(
          "#{Utils.safe_filename_string(server_name)}_stderr"
        )

        Utils.open_for_std_handle(@stderr_file) do |stderr|
          @server_handle = Utils.safe_popen(
            command_line,
            stdin: PIPE,
            stdout: PIPE,
            stderr: stderr,
            env: server_env
          )
        end

        @connection = StandardIOLanguageServerConnection.new(
          @project_directory,
          @server_handle.stdin,
          @server_handle.stdout,
          listener_factory: nil,
          workspace_conf_handler: ->(req) { workspace_conf_response(req) },
          notification_handler: default_notification_handler
        )

        @connection.start

        @connection.await_server_connection

        if @server_handle
          log_info "#{server_name} started with PID #{@server_handle.pid}"
        end

        true
      end

      def shutdown
        @server_info_mutex.synchronize do
          log_info "Shutting down #{server_name}..."

          @connection&.stop

          unless server_healthy?
            log_info "#{server_name} is not running"
            _reset
            return
          end

          if @server_handle
            log_info "Stopping #{server_name} with PID #{@server_handle.pid}"
          end
        end

        begin
          @server_info_mutex.synchronize { @connection.close }

          @connection&.close

          if @server_handle
            [@server_handle.stdout, @server_handle.stdin].each do |stream|
              stream.close if stream && !stream.closed?
            end

            @server_info_mutex.synchronize do
              Utils.wait_for_process_to_terminate(@server_handle, timeout: 30)
            end

            log_info "#{server_name} stopped"
          end
        rescue StandardError
          log_error "Error while stopping #{server_name}"
        end

        @server_info_mutex.synchronize { _reset }
      end

      # Returns an array of defined subcommands for this client.
      #
      # @return [Array<String>]
      def defined_subcommands
        subcommands = subcommands_map.keys.sort
        # We don't want to expose this subcommand because it's not really needed
        # for the user but it is useful in tests for teardown.
        subcommands.delete("StopServer")
        subcommands
      end

      # This method should return a hash where each key represents the client
      # command name and its value is a lambda in this form:
      #   (self, request_data, args) -> method
      #
      # where "method" is the call to the client method with corresponding
      # parameters. See the already implemented clients for examples.
      def subcommands_map
        {}
      end

      def user_commands_help_message
        subcommands = defined_subcommands
        if subcommands.empty?
          "This client has no supported subcommands."
        else
          "Supported subcommands are:\n" \
            "#{subcommands.join("\n")}\n" \
            "See the docs for information on what they do."
        end
      end

      def on_file_ready_to_parse(request_data) end

      def on_file_save(request_data) end

      def on_buffer_visit(request_data) end

      def on_buffer_unload(request_data) end

      def on_insert_leave(request_data) end

      def on_user_command(arguments, request_data)
        if !arguments || arguments.empty?
          raise ArgumentError, user_commands_help_message
        end

        command_map = subcommands_map

        begin
          command = command_map.fetch(arguments[0])
        rescue KeyError
          raise ArgumentError, user_commands_help_message
        end

        command.call(self, request_data, arguments[1..])
      end

      def _current_filetype(filetypes)
        supported = supported_filetypes

        filetypes.each do |filetype|
          return filetype if supported.include?(filetype)
        end

        filetypes[0]
      end

      def supported_filetypes
        Set.new
      end

      def debug_info(_request_data)
        ""
      end

      def server_ready?
        server_healthy?
      end

      def server_healthy?
        true
      end

      def poll_for_messages(request_data)
        poll_for_messages_inner(request_data, MESSAGE_POLL_TIMEOUT)
      end

      def poll_for_messages_inner(_request_data, _timeout)
        false
      end

      def get_settings(_mod, _request_data)
        # TODO: Figure out an elegant way to do this in ruby
        {}
      end
    end
  end
end
