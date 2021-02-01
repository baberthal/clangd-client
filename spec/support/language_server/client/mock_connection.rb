# frozen_string_literal: true

require "language_server/client/language_server_connection"

module Spec
  class MockConnection < LS::Client::LanguageServerConnection
    def initialize(workspace_conf_handler: nil)
      super(nil, listener_factory: nil,
                 workspace_conf_handler: workspace_conf_handler)
    end

    def try_server_connection_blocking() = true

    def shutdown; end

    def write_data(data) end

    def read_data(_size = -1) = ""

    def _notifications
      @notifications
    end
  end
end
