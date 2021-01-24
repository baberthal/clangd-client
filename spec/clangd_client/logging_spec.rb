# frozen_string_literal: true

RSpec.describe ClangdClient::Logging, logging_helpers: true do
  subject(:obj) { klass.new }

  let(:klass) { Class.new { include ClangdClient::Logging } }

  after do
    described_class.level = Logger::INFO
  end

  describe "setting a custom logger" do
    it "does not accept a logger that does not conform to the protocol" do
      expect { described_class.logger = "" }.to raise_error ArgumentError
    end

    it "accepts a custom logger that conforms to the protocol" do
      expect { described_class.logger = Logger.new($stdout) }.not_to raise_error
    end
  end

  describe "logging with a custom logger" do
    before do
      @readpipe, @writepipe = IO.pipe
      @custom_logger = Logger.new(@writepipe)
      described_class.logger = @custom_logger
      described_class.level  = Logger::INFO
    end

    after do
      [@readpipe, @writepipe].each do |pipe|
        pipe&.close
      end
    end

    it "outputs debug logs at log level DEBUG" do
      described_class.level = Logger::DEBUG
      obj.log_debug("hi")

      str = nil
      expect { str = @readpipe.read_nonblock(512) }.not_to raise_error
      expect(str).not_to be_nil
    end

    it "does not output debug logs if log level is not DEBUG" do
      described_class.level = Logger::INFO
      obj.log_debug("hello")
      expect { @readpipe.read_nonblock(512) }.to \
        raise_error IO::EAGAINWaitReadable
    end

    it "is usable at the module level for logging" do
      allow(@custom_logger).to receive(:add)
      described_class.log_msg("hey")
      expect(@custom_logger).to have_received(:add).with(Logger::INFO, "hey")
    end
  end

  describe "logging with the default logger" do
    it "logs at debug level if debug logging is enabled" do
      described_class.level = Logger::DEBUG
      out = with_redirected_stdout { obj.log_debug("HEY!") }

      expect(out).to include "HEY!"
      expect(out).to include "DEBUG"
    end

    it "is usable at the module level for logging" do
      out = with_redirected_stdout { described_class.log_msg("HEY!") }
      expect(out).to include "HEY!"
    end
  end
end
