# frozen_string_literal: true

require "logger"

module ClangdClient
  # Module to hold logging abstractions.
  module Logging
    # Simple formatter which only displays the message
    class SimpleFormatter < ::Logger::Formatter
      # This method is invoked when a log event occurs
      def call(_severity, _timestamp, _progname, msg)
        "#{msg.is_a?(String) ? msg : msg.inspect}\n"
      end
    end

    class << self
      # Default logger to use
      # @return [Logger]
      attr_reader :logger

      # Returns the level of the logger.
      #
      # @return [Logger::Severity]
      def level
        @logger ? @logger.level : nil
      end

      # Sets the level of the logger.
      #
      # @param value [Logger::Severity] One of the constants in
      #   +Logger::Severity+.
      def level=(value)
        @logger = ::Logger.new($stdout) if @logger.nil?
        @logger.level = value
      end

      # Sets a custom logger.
      #
      # @param custom_logger [Logger] The custom logger to use.
      def logger=(custom_logger)
        %i[level level= debug info warn error fatal unknown].each do |method|
          unless custom_logger.respond_to?(method)
            raise ArgumentError, "logger must respond to #{method}"
          end
        end

        @logger = custom_logger
      end

      # Logs a message at a given level.
      #
      # @param msg [#to_s] Message to log
      # @param level [Logger::Severity] The severity level at which to log +msg+
      def log_msg(msg, level = ::Logger::INFO)
        return unless @logger

        @logger.add(level, msg)
      end
    end

    # Default logger to $stdout
    self.logger      = ::Logger.new($stdout)
    logger.level     = Logger::INFO
    logger.formatter = Logging::SimpleFormatter.new

    def logger
      Logging.logger
    end

  module_function

    # Log a message at DEBUG level
    # @param msg [#to_s] Message to log
    def log_debug(msg = nil)
      Logging.log_msg(msg || yield, ::Logger::DEBUG)
    end
    public :log_debug

    # Log a message at INFO level
    # @param msg [#to_s] Message to log
    def log_info(msg = nil)
      Logging.log_msg(msg || yield, ::Logger::INFO)
    end
    public :log_info

    # Log a message at ERROR level (and possibly a backtrace)
    # @param msg [#to_s] Message to log
    # @param err [StandardError] Optional error to log
    def log_error(msg, err = nil)
      log_msg = msg
      log_msg += ": #{err}\n\t#{err.backtrace.join("\n\t")}\n" if err
      Logging.log_msg(log_msg, ::Logger::ERROR)
    end
    public :log_error
  end
end
