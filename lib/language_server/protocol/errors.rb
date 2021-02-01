# frozen_string_literal: true

module LanguageServer
  module Protocol
    class Error < StandardError; end

    # Raised when trying to convert a server URI to a file path but the scheme
    # was not supported. Only the file:// scheme is supported.
    class InvalidURIError < Error; end

    # Errors from the Language server protocol spec.
    module Errors
      # @private
      #
      # This is a base class for all errors defined in the protocol.
      class BaseProtocolError; end # rubocop:disable Lint/EmptyClass

      def self.create(code, reason)
        Class.new(BaseProtocolError) do
          define_method(:code) { code }
          define_method(:reason) { reason }
          define_singleton_method(:code) { code }
          define_singleton_method(:reason) { reason }
        end
      end

      # From
      # https://microsoft.github.io/language-server-protocol/specification#response-message
      #
      # JSON RPC
      ParseError     = Errors.create(-32_700, "Parse error")
      InvalidRequest = Errors.create(-32_600, "Invalid request")
      MethodNotFound = Errors.create(-32_601, "Method not found")
      InvalidParams  = Errors.create(-32_602, "Invalid parameters")
      InternalError  = Errors.create(-32_603, "Internal error")

      # The following sentinel values represent the range of errors for "user
      # defined" server errors. We don't define them as actual errors, as they
      # are just representing a valid range.
      #
      # export const serverErrorStart: number = -32099;
      # export const serverErrorEnd: number = -32000;

      # LSP defines the following custom server errors
      ServerNotInitialized = Errors.create(-32_002, "Server not initialized")
      UnknownErrorCode     = Errors.create(-32_001, "Unknown error code")

      # LSP request errors
      RequestCancelled = Errors.create(-32_800, "The request was cancelled")
      ContentModified  = Errors.create(-32_801, "Content was modified")

      def self.lookup(symbol)
        return symbol if symbol.is_a?(BaseProtocolError)

        raise NameError, "Unknown error: #{symbol}" unless const_defined?(symbol)

        const_get(symbol)
      end
    end
  end
end
