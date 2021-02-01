# frozen_string_literal: true

module LanguageServer
  module Client
    # Represents a blocking pending request.
    class Response
      def initialize(&response_callback)
        @event             = Concurrent::Event.new
        @message           = nil
        @response_callback = response_callback
      end

      def response_received(message)
        @message = message
        @event.set
        @response_callback&.call(self, message)
      end

      # Called when the server is shutting down
      def abort
        response_received(nil)
      end

      # Called by clients to wait synchronously for either a response to be
      # received or for `timeout` seconds to have passed.
      #
      # Returns the message, or:
      #   - throws ResponseFailedException if the request fails
      #   - throws ResponseTimeoutException in case of a timeout
      #   - throws ResponseAbortedException in case the server is shut down
      def await_response(timeout)
        @event.wait(timeout)

        raise ResponseTimeoutError, "Response Timeout" unless @event.set?

        raise ResponseAbortedError, "Response aborted" if @message.nil?

        if @message.key?("error")
          error = @message["error"]
          raise ResponseFailedError, "Request failed: #{error['code'] || 0}: " \
            "#{error['message'] || 'No message'}"
        end

        @message
      end
    end
  end
end
