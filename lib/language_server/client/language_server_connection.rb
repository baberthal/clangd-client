# frozen_string_literal: true

require "language_server/common/logging"
require "language_server/client/response"
require "language_server/protocol"
require "forwardable"
require "abc"

module LanguageServer
  module Client
    # Represents a connection to the language server.
    #
    # TODO: Document
    class LanguageServerConnection
      include Logging
      extend Forwardable
      extend ABC::ABCMeta

      CONNECTION_TIMEOUT = 5
      MAX_QUEUED_MESSAGES = 500

      def_delegators :@thread, :join, :alive?

      # @!method try_server_connection_blocking
      # Connect to the server and return when the connection is established.
      #
      # @return [Void]
      abstract_method :try_server_connection_blocking

      # @!method connected?
      # Return +true+ if the socket is connected.
      #
      # @return [Boolean]
      abstract_method :connected?

      # @!method write_data(data)
      # Write some data to the server.
      #
      # @param data [String] Data to write to the socket.
      #
      # @return [Void]
      abstract_method :write_data

      # @!method read_data(size = -1)
      # Read some data from the server, blocking until it becomes available.
      #
      # @param size [Integer] Number of bytes to read, or -1 to read until a new
      #   line.
      #
      # @return [Void]
      abstract_method :read_data

      def _cancel_listeners
        @listeners.map(&:stop)
      end

      def shutdown
        _cancel_listeners
      end

      def initialize(project_directory, listener_factory:,
                     workspace_conf_handler:, notification_handler: nil)
        @project_directory      = project_directory
        @listener_factory       = listener_factory
        @workspace_conf_handler = workspace_conf_handler
        @last_id                = 0
        # TODO: Consider using Concurrent::Map here
        @responses      = {}
        @response_mutex = Mutex.new
        # TODO: Consider using new Ractor API here
        @notifications = SizedQueue.new(MAX_QUEUED_MESSAGES)

        @connection_event     = Concurrent::Event.new
        @stop_event           = Concurrent::Event.new
        @notification_handler = notification_handler

        @collector = RejectCollector.new
        @listeners = []

        @start_mutex = Mutex.new
        @start_mutex.lock

        @thread = Thread.new do
          @start_mutex.lock
          run
        end
      end

      def collect_apply_edits(collector)
        old_collector = @collector
        @collector = collector
        yield
      ensure
        @collector = old_collector
      end

      def start
        @start_mutex.unlock
      end

      def run
        log_debug "Starting server connection..."

        # Wait for the connection to fully establish (this runs in the thread
        # context, so we block until a connection is received or there is
        # a timeout, which throws an Exception)
        try_server_connection_blocking
        @connection_event.set

        # Blocking loop which reads whole messages and calls
        # {#_dispatch_message}.
        _read_messages
      rescue LanguageServerConnectionStopped
        @response_mutex.synchronize do
          @responses.each do |_, response|
            response.abort
          end
          @responses.clear
        end

        log_debug "Connection was closed cleanly"
      rescue StandardError => e
        log_error "The language server communication channel closed " \
          "unexpectedly. Issue a restart_server command to recover. (#{e})"

        # Abort any outstanding requests.
        @response_mutex.synchronize do
          @responses.each do |_, response|
            response.abort
          end
          @responses.clear
        end

        shutdown
      end

      def stop
        @stop_event.set
      end

      def close
        shutdown
        begin
          join(0.1)
        rescue StandardError
          log_error "Shutting down dispatch thread while inactive"
        end
      end

      def stopped?
        @stop_event.set?
      end

      def next_request_id
        @response_mutex.synchronize do
          @last_id += 1
          @last_id
        end
      end

      # Issue a request to the server and return immediately. If a response
      # needs to be handled, supply a block taking (response, message). Note
      # `response` is the instance of {Response} and message is the message
      # received from the server.
      #
      # @return [Response] the instance of Response that was created.
      def get_response_async(request_id, message, &response_callback)
        response = Response.new(&response_callback)

        @response_mutex.synchronize do
          # TODO: Consider using pattern matching here
          if @responses.key?(request_id)
            raise "Assertion failed: response already exists"
          end

          @responses[request_id] = response
        end

        log_debug "TX: Sending message: #{message.inspect}"

        write_data(message)

        response
      end

      # Issue a request to the server and await the response. See
      # {Response#await_response} for return values and errors.
      def get_response(request_id, message, timeout)
        response = get_response_async(request_id, message)
        response.await_response(timeout)
      end

      # Issue a notification to the server. A notification is "fire and forget";
      # no response will be received and nothing is returned.
      def send_notification(message)
        log_debug "TX: Sending notification: #{message.inspect}"
        write_data(message)
      end

      # Send a response message. This is a message which is not a notification,
      # but still requires not response from the server.
      def send_response(message)
        log_debug "TX: Sending response: #{message.inspect}"
        write_data(message)
      end

      # Client implementations should call this after starting the server and
      # the message pump {#start} to await successful connection to the server
      # being established.
      #
      # Returns no meaningful value, but may throw
      # {LanguageServerConnectionTimeout} in the event that the server does not
      # connect promptly. In that case, clients should shut down their server
      # and reset their state.
      def await_server_connection
        @connection_event.wait(CONNECTION_TIMEOUT)

        return if @connection_event.set?

        # TODO: Rename this error
        raise LanguageServerConnectionTimeout,
              "Timed out waiting for server to connect"
      end

      # Main message pump. Within the message pump thread context, reads
      # messages from the socket/stream by calling {#read_data} in a loop and
      # dispatch complete messages by calling {#_dispatch_message}.
      #
      # When the server is shut down cleanly, raises
      # {LanguageServerConnectionStopped}.
      def _read_messages
        data = +""

        loop do
          data, read_bytes, headers = _read_headers(data)

          # FIXME: We could try to recover from this, but the message pump just
          # fails
          unless headers.key?("Content-Length")
            raise "Missing 'Content-Length' header"
          end

          content_length = headers["Content-Length"].to_i

          # We need to read content_length bytes for the payload of this
          # message. This may be in the remainder of `data`, but we also may
          # need to read more data from the socket.
          content = +""
          content_read = 0

          if read_bytes < data.length
            # There are bytes left in `data`, use them
            data = data[read_bytes..]

            # Read up to content_length bytes from data
            content_to_read = [content_length, data.length].min
            content += data[0..content_to_read]
            content_read += content.length
            read_bytes = content_to_read
          end

          while content_read < content_length
            # There is more content to read, but `data` is exhausted. Read more
            # from the socket.
            data = read_data(content_length - content_read)
            content_to_read = [content_length - content_read, data.length].min
            content += data[0..content_to_read]
            content_read += content.length
            read_bytes = content_to_read
          end

          log_debug "RX: Received message: #{content.inspect}"

          _dispatch_message(LS::Protocol.parse(content))

          # We only consumed `content.length` bytes of data. If there is more,
          # we start again, but only with the remainder and look for headers.
          data = data[read_bytes..]
        end
      end

      # Starting with the data in `data`, read headers from the stream/socket
      # until a full set of headers has been consumed. Returns an array:
      #   - data: any remaining unused data from `data` or the socket
      #   - read_bytes: the number of bytes of returned data that have been
      #                 consumed
      #   - headers: a hash whose keys are the headerr names and whose values
      #              are the header values.
      def _read_headers(data)
        # TODO: Consider adding a HeadersParser class that parses and returns
        # headers.
        #
        # LSP defines only 2 headers, of which only one is useful
        # (Content-Length). Headers end with an empty line, and there is no
        # guarantee that a single socket or stream read will contain only
        # a single message, or even a whole message.
        headers_complete = false
        prefix = +""
        headers = {}

        until headers_complete
          read_bytes = 0
          last_line = 0
          data = read_data if data.empty?

          while read_bytes < data.length
            if data[read_bytes..][0] == "\n"
              line = prefix + data[last_line..read_bytes].strip
              prefix = ""
              last_line = read_bytes

              if line.strip.empty?
                headers_complete = true
                read_bytes += 1
                break
              else
                begin
                  key, value = line.split(":", 2)
                  headers[key.strip] = value.strip
                rescue StandardError
                  log_error "Received invalid protocol data from server: #{line}"
                  raise
                end
              end
            end

            read_bytes += 1
          end

          unless headers_complete
            prefix = data[last_line..]
            data = +""
          end
        end

        [data, read_bytes, headers]
      end

      # TODO: This needs to be retrofitted to use the listen gem
      def _handle_dynamic_registrations(request)
        request["params"]["registrations"].each do |reg|
          next unless reg["method"] == "workspace/didChangeWatchedFiles"

          globs = []
          reg["registerOptions"]["watchers"].each do |watcher|
            pattern = File.join(@project_directory, watcher["globPattern"])
            pattern = File.join(pattern, "**") if File.directory?(pattern)
            globs.push(pattern)
          end
          listener = Observer.new
          listener.schedule(@listener_factory.call(globs),
                            @project_directory,
                            recursive: true)
          listener.start
          @listeners.push(listeners)
        end
        send_response(LS::P.void(request))
      end

      def _server_to_client_request(request)
        method = request["method"]
        case method
        when "workspace/applyEdit"
          @collector.collect_apply_edit(request, self)
        when "workspace/configuration"
          response = @conf_handler.call(request)
          if response.nil?
            send_response(Protocol.reject(request, :MethodNotFound))
          else
            send_response(Protocol.accept(request, response))
          end
        when "client/registerCapability"
          _handle_dynamic_registrations(request)
        when "client/unregisterCapability"
          request["params"]["unregistrations"].each do |reg|
            if reg["method"] == "workspace/didChangeWatchedFiles"
              _cancel_listener_threads
            end
          end
          send_response(Protocol.void(request))
        else
          # Reject the request
          send_response(Protocol.reject(request, :MethodNotFound))
        end
      end

      # Called in the message pump thread context when a complete message was
      # read. For responses, calls the Response object's #response_received
      # method, or for notifications, simply accumulates them in a Queue which
      # is polled by the long-polling mechanism.
      def _dispatch_message(message)
        if message.key?("id")
          message_id = message["id"]
          return if message_id.nil?

          if message.key?("method")
            # This is a server->client request, which requires a response
            _server_to_client_request(message)
          else
            @response_mutex.synchronize do
              raise "Assertion failed" unless @responses.key?(message_id)

              @responses[message_id].response_received(message)
              @responses.delete(message_id)
            end
          end
        else
          # This is a notification if it doesn't have an id
          _add_notification_to_queue(message)

          # If there is an immediate (in-message-pump-thread) handler
          # configured, call it.
          if @notification_handler
            begin
              @notification_handler.call(self, message)
            rescue StandardError
              logger.error("Handling message in poll thread failed: #{message}")
            end
          end
        end
      end

      # TODO: This could probably be a Ractor
      def _add_notification_to_queue(message)
        loop do
          begin
            @notifications.push(message, true)
            return
          rescue ThreadError
            # This is only a theoretical possibility to prevent this thread
            # blocking in the unlikely event that all elements are removed from
            # the queue between put_nowait and get_nowait.
          end

          begin
            # The queue (ring buffer) is full.  This indicates either a slow
            # consumer or the message poll is not running. In any case, rather
            # than infinitely queueing, discard the oldest message and try
            # again.
            @notifications.pop(true)
          rescue ThreadError
            # This is only a theoretical possibility to prevent this thread
            # blocking in the unlikely event that all elements are removed from
            # the queue between put_nowait and get_nowait.
          end
        end
      end
    end

    # Collects rejects
    class RejectCollector
      def collect_apply_edit(request, conn)
        conn.send_response(LS::Protocol.apply_edit_response(request, false))
      end
    end
  end
end
