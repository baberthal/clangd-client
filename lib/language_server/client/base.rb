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
          @server_handle = Utils.popen(
            command_line,
            stdin: Subprocess::PIPE,
            stdout: Subprocess::PIPE,
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

      # Send the shutdown and possibly exit request to the server.
      # Implementations must call this prior to closing the
      # LanguageServerConnection or killing the downstream server.
      def shutdown_server
        # Language server protocol requires ordersly shutdown of the downstream
        # server by first sending a shutdown request, and on its completion
        # sending an exit notification (which does not receive a response). Some
        # buggy servers exit on receipt of the shutdown request, so we handle
        # that too.
        if _server_initialized?
          request_id = connection.next_request_id
          msg = LS::Protocol.shutdown(request_id)

          begin
            connection.get_response(request_id, msg, REQUEST_TIMEOUT_INITIALIZE)
          rescue ResponseAbortedError
            # When the language server dies handling the shutdown request, it is
            # aborted. Just return - we're done.
            return
          rescue StandardError
            # Ignore other errors from the server and send the exit request
            # anyway.
            log_error "Shutdown request failed. Ignoring."
          end
        end

        connection.send_notification(LS::Protocol.exit) if server_healthy?

        # If any threads are waiting for the initialize echange to complete,
        # release them, as there is no chance of getting a response now.
        if !@initialize_response.nil? && !@initialize_event.set?
          @initialize_response = nil
          @initialize_event.set
        end
      end

      def _restart_server(request_data, *args, **options)
        shutdown
        _start_and_initialize_server(request_data, *args, **options)
      end

      # Returns +true+ if the server is running and the initialization exchange
      # has completed successfully. Implementations must not issue requests
      # until this method returns +true+.
      def _server_initialized?
        return false unless server_healthy?

        # We already got the initialize response
        return true if @initialize_event.set?

        # We never sent the initialize response
        return false if @initialize_response.nil?

        # Initialize request in progress. Will be handled asynchronously.
        false
      end

      def server_healthy?
        if command_line
          Utils.process_running?(@server_handle)
        else
          @connection&.connected?
        end
      end

      def server_ready?
        _server_initialized?
      end

      # A string representing a human-readable name of the server.
      #
      # @return [String]
      #
      # ABSTRACT
      def server_name
        raise NotImplementedError
      end

      # +nil+, or a hash containing environment variables for ther server
      # process.
      #
      # @return [Hash{String=>String,nil}, nil]
      def server_env
        nil
      end

      # An override in a concrete class needs to return a list of CLI arguments
      # for starting the LSP server.
      #
      # @return [Array<String>]
      #
      # ABSTRACT
      def command_line
        raise NotImplementedError
      end

      # If the concrete client wants to response to workspace/configuration
      # requests, it should override this method.
      def workspace_conf_response(_request)
        nil
      end

      # If the server has special capabilities, override this method.
      #
      # @return [Hash]
      def extra_capabilities
        {}
      end

      # Returns the list of server logs, other than stderr.
      #
      # @return [Array<String>]
      def additional_log_files
        []
      end

      # An Array of DebugInfoItems
      #
      # @return [Array<DebugInfoItem>]
      def extra_debug_items(_request_data)
        []
      end

      def debug_info(request_data)
        @server_info_mutex.synchronize do
          extras = common_debug_items + extra_debug_items(request_data)
          logfiles = [@stdout_file, @stderr_file] + additional_log_files
          return DebugInfoItem.new(
            name: server_name,
            handle: @server_handle,
            executable: command_line,
            port: @connection_type == :tcp ? @port : nil,
            logfiles: logfiles,
            extras: extras
          )
        end
      end

      # Starts the server and sends the initilize request, assuming the start is
      # successful. +args+ and +options+ are passed through to ther underlying
      # call to {#start_server}. In general, clients don't need to call this as
      # it is called automatically in {#on_file_ready_to_parse}, but this may
      # be used in client subcommands that require restarting the underlying
      # server.
      def _start_and_initialize_server(request_data, *args, **options)
        @server_started = false
        # @extra_conf_dir = _get_settings_from_extra_conf(request_data)

        # Only attempt to start the server once. Set this after above call as it
        # may throw an error.
        @server_started = true

        if start_server(request_data, *args, **options)
          _send_initialize(request_data)
        end
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

      def on_file_ready_to_parse(request_data)
        if !server_healthy? && !@server_started
          _start_and_initialize_server(request_data)
        end

        return unless server_healthy?

        unless @initialize_event.set?
          @on_file_ready_to_parse_handlers.reverse.each do |handler|
            _on_initialize_complete(handler)
          end
          return
        end

        @on_file_ready_to_parse_handlers.reverse.each do |handler|
          handler.call(self, request_data)
        end

        # TODO: Finish this up
      end

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

      def poll_for_messages(request_data)
        poll_for_messages_inner(request_data, MESSAGE_POLL_TIMEOUT)
      end

      def poll_for_messages_inner(request_data, timeout)
        # If there are messages pending in the queue, return them immediately
        messages = _get_pending_messages(request_data)
        return messages if messages

        # Otherwise, block until we get one or we hit the timeout
        _await_server_messages(request_data, timeout)
      end

      # Convert any pending notifications to messages and return them in an
      # Array.  If there are no messages pending, returns an empty Array.
      # Returns +false+ if an error occured and no further polling should be
      # attempted.
      #
      # @return [Array, false]
      def _get_pending_messages(request_data)
        messages = []

        return messages unless @initialize_event.set?

        begin
          loop do
            return false unless connection

            notification = connection._notifications.pop(true)
            message = convert_notification_to_message(request_data, notification)

            messages.push(message) if message
          end
        rescue ThreadError
          # We drained the queue
          nil
        end

        messages
      end

      # Block until we receive a notification, or a timeout occurs.
      #
      # Returns one on the following:
      #   - an Array containing a single message
      #   - +true+ if a tiemout occurred, and the poll should be restarted
      #   - +false+ if an error occured, and no further polling should be
      #     attempted
      def _await_server_messages(request_data, timeout)
        loop do
          unless @initialize_event.set?
            @initialize_event.wait(timeout)
            return !@server_started || @initialize_event.set?
          end

          return false unless connection

          notification = connection._notifications.pop(timeout: timeout)
          message = convert_notification_to_message(notification, request_data)

          return [message] if message
        rescue ThreadError
          return true
        end
      end

      def default_notification_handler
        ->(_, notification) { handle_notification_in_poll_thread(notification) }
      end

      def handle_notification_in_poll_thread(notification) end

      def convert_notification_to_message(request_data, notification) end

      def _update_server_with_file_contents(request_data)
        @server_info_mutex.synchronize do
          _update_dirty_files_under_lock(request_data)
          files_to_purge = _update_saved_files_under_lock(request_data)
          _purge_missing_files_under_lock(files_to_purge)
        end
      end

      def _update_dirty_files_under_lock(request_data) end

      def _update_saved_files_under_lock(request_data) end

      def _purge_missing_files_under_lock(files_to_purge) end

      def get_settings(_mod, _request_data)
        # TODO: Figure out an elegant way to do this in ruby
        {}
      end
    end
  end
end
