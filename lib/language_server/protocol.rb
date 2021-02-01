# frozen_string_literal: true

require "language_server/protocol/gem_version"

require "language_server/protocol/constants"
require "language_server/protocol/errors"
require "language_server/protocol/server_file_state"

require "json"
require "uri"

module LanguageServer
  # Module for LanguageServer Protocol-related code.
  #
  # TODO: The various methods in this module should probably each be their own
  # class.
  module Protocol
    # Builds a JSON RPC request message with the supplied ID, method, and method
    # parameters.
    def self.build_request(request_id, method, parameters)
      _build_message_data(
        "id" => request_id,
        "method" => method,
        "params" => parameters
      )
    end

    # Builds a JSON RPC notification message with the supplied method and method
    # parameters.
    def self.build_notification(method, parameters)
      _build_message_data(
        "method" => method,
        "params" => parameters
      )
    end

    # Builds a JSON RPC response message to respond to the supplied `request`
    # message. `parameters` should contain either 'error' or 'result'.
    def self.build_response(request, parameters)
      message = { "id" => request["id"] }
      message.update(parameters)
      _build_message_data(message)
    end

    # Builds the language server initialize request.
    def self.initialize_request(request_id, project_directory,
                                extra_capabilities, settings)
      capabilities = {}
      build_request(request_id, "initialize", {
        "processId" => Process.pid,
        "rootPath": project_directory,
        "rootUri": FIXME,
        "initializationOptions": settings,
        "capabilities": update_dict(capabilities, extra_capabilities)
      })
    end

    def self.initialized
      build_notification("initialized", {})
    end

    def self.shutdown(request_id)
      build_request(request_id, "shutdown", nil)
    end

    def self.exit
      build_notification("exit", nil)
    end

    def self.accept(request, result)
      msg = { "result" => result }
      build_response(request, msg)
    end

    def self.reject(request, request_error, data = nil)
      request_error = Errors.lookup(request_error)

      msg = {
        "error" => {
          "code" => request_error.code,
          "message" => request_error.reason
        }
      }

      msg["error"]["data"] = data if data

      build_response(request, msg)
    end

    def self.void(request)
      accept(request, nil)
    end

    def self.apply_edit_response(request, applied)
      msg = { "applied" => applied }
      accept(request, msg)
    end

    def self.did_change_watched_files(path, kind)
      build_notification("workspace/didChangeWatchedFiles", {
        "changes" => [{
          "uri": file_path_to_uri(path),
          "type" => FILE_EVENT_KIND[kind]
        }]
      })
    end

    def self.did_change_configuration(config)
      build_notification("workspace/didChangeConfiguration", {
        "settings" => config
      })
    end

    def self.did_open_text_document(file_state, file_types, file_contents)
      build_notification("textDocument/didOpen", {
        "textDocument" => {
          "uri" => file_path_to_uri(file_state.filename),
          "languageId" => file_types.join("/"),
          "version" => file_state.version,
          "text" => file_contents
        }
      })
    end

    def self.did_change_text_document(file_state, file_contents)
      build_notification("textDocument/didChange", {
        "textDocument" => {
          "uri" => file_path_to_uri(file_state.filename),
          "version" => file_state.version
        },
        "contentChanges" => file_contents.nil? ? [] : [{ "text" => file_contents }]
      })
    end

    def self.did_save_text_document(file_state, file_contents)
      params = {
        "textDocument" => {
          "uri" => file_path_to_uri(file_state.filename),
          "version" => file_state.version
        }
      }
      params.update({ "text" => file_contents }) unless file_contents.nil?
      build_notification("textDocument/didSave", params)
    end

    def self.did_close_text_document(file_state)
      build_notification("textDocument/didClose", {
        "textDocument" => {
          "uri" => file_path_to_uri(file_state.filename),
          "version" => file_state.version
        }
      })
    end

    def self._build_message_data(message)
      message["jsonrpc"] = "2.0"
      # NOTE: We have to sort the keys here to workaround a limitation in
      # clangd where it requires keys to be in a specific order, due to
      # a somewhat naive JSON/YAML parser.
      data = JSON.generate(message.sort { |kv1, kv2| kv1[0] <=> kv2[0] }.to_h)
      "Content-Length: #{data.bytesize}\r\n\r\n" + data
    end

    # Returns the raw language server message payload into a ruby hash
    def self.parse(data)
      JSON.parse(data)
    end

    def self.file_path_to_uri(file_name)
      URI.join("file:", file_name).to_s
    end

    def self.uri_to_file_path(uri)
      parsed_uri = URI.parse(uri)

      raise InvalidURIError, uri if parsed_uri.scheme != "file"

      File.absolute_path(parsed_uri.path)
    end
  end
end

LS = LanguageServer unless defined?(LS)
LS::P = LanguageServer::Protocol unless LS.const_defined?(:P)
