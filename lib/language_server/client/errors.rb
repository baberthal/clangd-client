# frozen_string_literal: true

module LanguageServer
  module Client
    # Base Error class for LanguageServer::Client
    class Error < StandardError; end

    # Raised by {LanguageServerConnection} if a request exceeds the supplied
    # time-to-live.
    class ResponseTimeoutError < Error; end

    # Raised by {LanguageServerConnection} if a request is cancelled due to the
    # server shutting down.
    class ResponseAbortedError < Error; end

    # Raise by {LanguageServerConnection} if a request returns an error.
    class ResponseFailedError < Error; end

    # Raised by {LanguageServerConnection} if the connection to the server is
    # not established within the specified timeout.
    class LanguageServerConnectionTimeout < Error; end

    # Internal error raised by {LanguageServerConnection} when the server is
    # successfully shut down according to a user request.
    class LanguageServerConnectionStopped < Error; end
  end
end
