# frozen_string_literal: true

require "json"

module ClangdClient
  # Stores options from the user, either set in vim or the default.
  #
  # TODO: Consider making this a Singleton
  class UserOptions
    def self.default_options
      settings_path = File.expand_path("default_settings.json", __dir__)
      JSON.parse(File.read(settings_path))
    end

    def initialize
      @_user_options = {}
    end

    def update(new_options)
      @_user_options = Hash[new_options].freeze
    end

    alias set_all update

    def all
      @_user_options
    end

    alias get_all all

    def value(key)
      @_user_options[key]
    end

    alias [] value
  end
end
