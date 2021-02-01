# frozen_string_literal: true

module LanguageServer
  # Module to include in classes where one would like to run a process in
  # a thread that is able to be started.
  #
  # Classes that include this module must define a `run` method. This method is
  # what will be run inside of the thread context.
  #
  # To start the thread, call the {#start} method.
  module ThreadStartable
    def initialize(*)
      super

      @start_mutex = Mutex.new
      @start_mutex.lock

      @thread = Thread.new do
        @start_mutex.lock # Wait for #start to be called
        run
      end
    end

    # Unlocks the +start_mutex+, and runs the +run+ method in the thread
    # context.
    def start
      @start_mutex.unlock
    end
  end
end
