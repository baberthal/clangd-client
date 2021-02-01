# frozen_string_literal: true

module LanguageServer
  # The constants defined in this file are from the Language Server Protocol
  # specification, described at
  # https://microsoft.github.io/language-server-protocol/specifications/specification-current/
  module Protocol
    # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_completion
    INSERT_TEXT_FORMAT = [
      nil, # 1-based
      "PlainText",
      "Snippet"
    ].freeze

    # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_completion
    ITEM_KIND = [
      nil, # 1-based
      "Text",
      "Method",
      "Function",
      "Constructor",
      "Field",
      "Variable",
      "Class",
      "Interface",
      "Module",
      "Property",
      "Unit",
      "Value",
      "Enum",
      "Keyword",
      "Snippet",
      "Color",
      "File",
      "Reference",
      "Folder",
      "EnumMember",
      "Constant",
      "Struct",
      "Event",
      "Operator",
      "TypeParameter"
    ].freeze

    # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#diagnostic
    SEVERITY = [
      nil, # 1-based
      "Error",
      "Warning",
      "Information",
      "Hint"
    ].freeze

    # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#workspace_didChangeWatchedFiles
    FILE_EVENT_KIND = {
      "create" => 1,
      "modify" => 2,
      "delete" => 3
    }.freeze

    # https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentSymbol
    SYMBOL_KIND = [
      nil, # 1-based
      "File",
      "Module",
      "Namespace",
      "Package",
      "Class",
      "Method",
      "Property",
      "Field",
      "Constructor",
      "Enum",
      "Interface",
      "Function",
      "Variable",
      "Constant",
      "String",
      "Number",
      "Boolean",
      "Array",
      "Object",
      "Key",
      "Null",
      "EnumMember",
      "Struct",
      "Event",
      "Operator",
      "TypeParameter"
    ].freeze
  end
end
