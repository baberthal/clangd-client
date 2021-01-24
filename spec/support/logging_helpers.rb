# frozen_string_literal: true

module Spec
  module LoggingHelpers
    def self.included(base)
      puts "LoggingHelpers included in #{base}"
    end
  end
end
