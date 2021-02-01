# frozen_string_literal: true

require "digest/sha1"

module LanguageServer
  module Protocol
    # Trivial hash-like class to hold ServerFileState for a given file path.
    # Language server clients must maintain one of these for each language
    # server connection.
    class ServerFileStateStore < Hash
      def self.new
        super { |h, k| h[k] = ServerFileState.new(k) }
      end
    end

    # A simple state machine for a particular file from the servers'
    # perspective, including version.
    class ServerFileState
      # States
      OPEN   = "Open"
      CLOSED = "Closed"

      # Actions
      CLOSE_FILE  = "Close"
      NO_ACTION   = "None"
      OPEN_FILE   = "Open"
      CHANGE_FILE = "Change"

      # The name of the file this ServerFileState represents.
      # @return [String]
      attr_reader :filename

      # The version number of the file this ServerFileState represents.
      # @return [Integer]
      attr_reader :version

      # The state of the represented file ("Open" or "Closed").
      # @return ["Open","Closed"]
      attr_reader :state

      # The sha1 checksum of the represented file's contents
      # @return [OpenSSL::Digest::SHA1]
      attr_reader :checksum

      # The contents of the file this ServerFileState represents.
      # @return [String]
      attr_reader :contents

      def initialize(filename)
        @filename = filename
        @version  = 0
        @state    = ServerFileState::CLOSED
        @checksum = nil
        @contents = ""
      end

      # Progress the state for a file to be updated due to being supplied in the
      # dirty buffers list. Returns any one of the actions to perform.
      def dirty_file_action(contents)
        new_checksum = _calculate_checksum(contents)

        if @state == ServerFileState::OPEN && checksum == new_checksum
          return ServerFileState::NO_ACTION
        end

        if @state == ServerFileState::CLOSED
          @version = 0
          action = ServerFileState::OPEN_FILE
        else
          action = ServerFileState::CHANGE_FILE
        end

        _send_new_version(new_checksum, action, contents)
      end

      # Progress the state for a file to be updated to to having previously been
      # opened, but no longer supplied in the dirty buffers list. Retursn one of
      # the Actions to perform: either NO_ACTION or CHANGE_FILE.
      def saved_file_action(contents)
        return ServerFileState::NO_ACTION if @state != ServerFileState::OPEN

        new_checksum = _calculate_checksum(contents)

        return ServerFileState::NO_ACTION if @checksum == new_checksum

        _send_new_version(new_checksum, ServerFileState::CLOSE_FILE, contents)
      end

      # Progress the state for a file which was closed in the client. Returns
      # one of the actions to perform: either NO_ACTION or CLOSE_FILE.
      def file_close_action
        if @state == ServerFileState::OPEN
          @state = ServerFileState::CLOSED
          return ServerFileState::CLOSE_FILE
        end

        @state = ServerFileState::CLOSED
        ServerFileState::NO_ACTION
      end

    private

      def _send_new_version(new_checksum, action, contents)
        @checksum  = new_checksum
        @version  += 1
        @state     = ServerFileState::OPEN
        @contents  = contents

        action
      end

      def _calculate_checksum(contents)
        Digest::SHA1.digest(contents)
      end
    end
  end
end
