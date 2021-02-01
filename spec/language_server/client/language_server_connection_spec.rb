# frozen_string_literal: true

RSpec.describe LS::Client::LanguageServerConnection do
  LanguageServer::Logging.level = Logger::DEBUG

  let(:conn) { Spec::MockConnection.new }

  describe "reading a partial message" do
    before do
      return_values = [
        "Content-Length: 10\n\n{\"abc\":",
        '""}'
      ]
      allow(conn).to receive(:read_data) do
        return_values.shift || raise(LS::Client::LanguageServerConnectionStopped)
      end
      allow(conn).to receive(:_dispatch_message)
    end

    it "properly reads the message, and calls _dispatch_message" do
      conn.run
      expect(conn).to have_received(:_dispatch_message).with({ "abc" => "" })
    end
  end

  describe "when a header is missing" do
    before do
      return_values = [
        "Content-NOTLENGTH: 10\r\n{\"abc\":",
        '""}',
        LS::Client::LanguageServerConnectionStopped
      ]
      allow(conn).to receive(:read_data).exactly(3).times do
        v = return_values.shift
        v.is_a?(LS::Client::LanguageServerConnectionStopped) ? raise(v) : v
      end
    end

    it "raises a StandardError when calling _read_messages" do
      expect { conn._read_messages }.to raise_error StandardError
    end
  end

  describe "aborting a request (with callback)" do
    let(:callback) { ->(a, b) {} }

    before do
      allow(conn).to receive(:read_data).and_raise(
        LS::Client::LanguageServerConnectionStopped
      )
      allow(callback).to receive(:call)
    end

    it "calls the response callback with nil" do
      response = conn.get_response_async(1, '{"test":"test"}', &callback)
      conn.run
      expect(callback).to have_received(:call).with(response, nil)
    end
  end

  describe "aborting a request (with await)" do
    before do
      allow(conn).to receive(:read_data).and_raise(
        LS::Client::LanguageServerConnectionStopped
      )
    end

    it "raises a ResponseAbortedError" do
      response = conn.get_response_async(1, '{"test":"test"}')
      conn.run
      expect do
        response.await_response(10)
      end.to raise_error LS::Client::ResponseAbortedError
    end
  end

  describe "when the connection dies" do
    before do
      allow(conn).to receive(:read_data).and_raise(IOError)
    end

    it "handles the exception and shuts down" do
      expect { conn.run }.not_to raise_error
    end
  end

  describe "when the connection times out" do
    before do
      stub_const("LS::Client::LanguageServerConnection::CONNECTION_TIMEOUT", 0.5)
      allow(conn).to receive(:try_server_connection_blocking) do
        raise RuntimeError
      end
    end

    it "await_server_connection raises LanguageServerConnectionTimeout" do
      conn.start
      expect do
        conn.await_server_connection
      end.to raise_error LS::Client::LanguageServerConnectionTimeout
      expect(conn.alive?).to be false
    end
  end

  describe "when #close is called twice" do
    before do
      allow(conn).to receive(:try_server_connection_blocking) do
        raise RuntimeError
      end
    end

    it "closes the connection and doesn't raise" do
      expect do
        conn.close
        conn.close
      end.not_to raise_error
    end
  end

  describe "adding connections to the queue" do
    before do
      stub_const("#{described_class}::MAX_QUEUED_MESSAGES", 2)
    end

    let(:notifications) { conn._notifications }

    it "properly stubs the MAX_QUEUED_MESSAGES constant" do
      expect(notifications.max).to eq 2
    end

    it "raises if the queue is empty" do
      expect { notifications.pop(true) }.to raise_error ThreadError
    end

    it "can dequeue if there is a notification in the queue" do
      conn._add_notification_to_queue("one")
      expect(notifications.pop(true)).to eq "one"
      expect { notifications.pop(true) }.to raise_error ThreadError
    end

    context "when the queue is full" do
      before do
        conn._add_notification_to_queue("one")
        conn._add_notification_to_queue("two")
      end

      it "can properly dequeue items" do
        expect(notifications.pop(true)).to eq "one"
        expect(notifications.pop(true)).to eq "two"
      end

      it "raises a ThreadError if the queue is empty" do
        notifications.pop(true)
        notifications.pop(true)
        expect { notifications.pop(true) }.to raise_error ThreadError
      end
    end

    context "when trying to add additional items to a full queue" do
      before do
        conn._add_notification_to_queue("one")
        conn._add_notification_to_queue("two")
        conn._add_notification_to_queue("three")
      end

      it "discards the earliest notifications" do
        expect(notifications.pop(true)).to eq "two"
        expect(notifications.pop(true)).to eq "three"
      end

      it "still raises if the queue is empty" do
        notifications.pop(true)
        notifications.pop(true)
        expect { notifications.pop(true) }.to raise_error ThreadError
      end
    end
  end

  describe "rejecting unsupported requests" do
    before do
      return_values = [
        "Content-Length: 26\r\n\r\n{\"id\":\"1\",\"method\":\"test\"}"
      ]
      allow(conn).to receive(:read_data) do
        return_values.shift || raise(LS::Client::LanguageServerConnectionStopped)
      end
      allow(conn).to receive(:write_data).and_call_original
    end

    let(:expected_response) do
      ["Content-Length: 79\r\n\r\n",
       '{"error":{' \
       '"code":-32601,' \
       '"message":"Method not found"' \
       '},' \
       '"id":"1",' \
       '"jsonrpc":"2.0"}'].join
    end

    it "tells the server that the method is unsupported" do
      conn.run
      expect(conn).to have_received(:write_data).with(expected_response)
    end
  end
end
