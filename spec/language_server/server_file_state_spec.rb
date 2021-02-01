# frozen_string_literal: true

RSpec.describe LanguageServer::Protocol::ServerFileState do
  let(:store) { LanguageServer::Protocol::ServerFileStateStore.new }
  let(:file1_state) { store["file1"] }
  let(:file2_state) { store["file2"] }

  describe "create new object" do
    it "has a version of 0 when it's a new object" do
      expect(file1_state.version).to eq 0
    end

    it "has no checksum when it's a new object" do
      expect(file1_state.checksum).to be nil
    end

    it "has a state of CLOSED when it's a new object" do
      expect(file1_state.state).to eq described_class::CLOSED
    end
  end

  describe "retrieve unchanged object" do
    it "has the same version" do
      expect(file1_state.version).to eq 0
    end

    it "has no checksum" do
      expect(file1_state.checksum).to be nil
    end

    it "still has a state of CLOSED" do
      expect(file1_state.state).to eq described_class::CLOSED
    end
  end

  describe "retrieve/create a different object" do
    it "has a version of 0" do
      expect(file2_state.version).to eq 0
    end

    it "has no checksum" do
      expect(file2_state.checksum).to be nil
    end

    it "has a state of closed" do
      expect(file2_state.state).to eq described_class::CLOSED
    end
  end

  describe "checking for refresh on closed file" do
    it "is a no-op" do
      expect(file1_state.saved_file_action("blah")).to \
        eq described_class::NO_ACTION
    end

    it "still has version 0" do
      expect(file1_state.version).to eq 0
    end

    it "still has no checksum" do
      expect(file1_state.checksum).to be nil
    end

    it "still has state of CLOSED" do
      expect(file1_state.state).to eq described_class::CLOSED
    end
  end

  describe "checking the next action" do
    let(:action) { file1_state.dirty_file_action("test contents") }

    before do
      action
    end

    it "progresses the state" do
      expect(action).to eq described_class::OPEN
    end

    it "increments the version" do
      expect(file1_state.version).to eq 1
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state OPEN" do
      expect(file1_state.state).to eq described_class::OPEN
    end
  end

  describe "replacing the same file" do
    let(:action) { file1_state.dirty_file_action("test contents") }

    before do
      action
    end

    it "is a no-op" do
      expect(file1_state.dirty_file_action("test contents")).to \
        eq described_class::NO_ACTION
    end

    it "still is version 1" do
      expect(file1_state.version).to eq 1
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state OPEN" do
      expect(file1_state.state).to eq described_class::OPEN
    end
  end

  describe "changing the file" do
    let(:action) { file1_state.dirty_file_action("test contents changed") }

    before do
      file1_state.dirty_file_action("test contents")
      action
    end

    it "returns CHANGE_FILE" do
      expect(action).to eq described_class::CHANGE_FILE
    end

    it "creates a new version" do
      expect(file1_state.version).to eq 2
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "still has state OPEN" do
      expect(file1_state.state).to eq described_class::OPEN
    end
  end

  describe "replacing the same file again" do
    let(:action) { file1_state.dirty_file_action("test contents changed") }

    before do
      file1_state.dirty_file_action("test contents")
      action
    end

    it "is a no-op" do
      expect(file1_state.dirty_file_action("test contents changed")).to \
        eq described_class::NO_ACTION
    end

    it "still is version 2" do
      expect(file1_state.version).to eq 2
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state OPEN" do
      expect(file1_state.state).to eq described_class::OPEN
    end
  end

  describe "checking for refresh without change" do
    let(:action) { file1_state.dirty_file_action("test contents changed") }

    before do
      file1_state.dirty_file_action("test contents")
      action
    end

    it "is a no-op" do
      expect(file1_state.saved_file_action("test contents changed")).to \
        eq described_class::NO_ACTION
    end

    it "still is version 2" do
      expect(file1_state.version).to eq 2
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state OPEN" do
      expect(file1_state.state).to eq described_class::OPEN
    end
  end

  describe "changing the same file" do
    let(:action) { file1_state.dirty_file_action("test contents changed again") }

    before do
      file1_state.dirty_file_action("test contents")
      file1_state.dirty_file_action("test contents changed")
      action
    end

    it "returns CHANGE_FILE" do
      expect(action).to eq described_class::CHANGE_FILE
    end

    it "creates a new version" do
      expect(file1_state.version).to eq 3
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state OPEN" do
      expect(file1_state.state).to eq described_class::OPEN
    end
  end

  describe "checking for refresh with change" do
    let(:action) { file1_state.dirty_file_action("test contents changed back") }

    before do
      file1_state.dirty_file_action("test contents")
      file1_state.dirty_file_action("test contents changed")
      file1_state.dirty_file_action("test contents changed again")
      action
    end

    it "returns CHANGE_FILE" do
      expect(action).to eq described_class::CHANGE_FILE
    end

    it "creates a new version" do
      expect(file1_state.version).to eq 4
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state OPEN" do
      expect(file1_state.state).to eq described_class::OPEN
    end
  end

  describe "closing an open file" do
    let(:action) { file1_state.file_close_action }

    before do
      file1_state.dirty_file_action("test contents")
      file1_state.dirty_file_action("test contents changed")
      file1_state.dirty_file_action("test contents changed again")
      file1_state.dirty_file_action("test contents changed back")
      action
    end

    it "progresses the state to CLOSE_FILE" do
      expect(action).to eq described_class::CLOSE_FILE
    end

    it "has the same version" do
      expect(file1_state.version).to eq 4
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state CLOSED" do
      expect(file1_state.state).to eq described_class::CLOSED
    end
  end

  describe "replacing a closed file" do
    let(:action) { file1_state.dirty_file_action("test contents again 2") }

    before do
      file1_state.dirty_file_action("test contents")
      file1_state.dirty_file_action("test contents changed")
      file1_state.dirty_file_action("test contents changed again")
      file1_state.dirty_file_action("test contents changed back")
      file1_state.file_close_action
      action
    end

    it "opens the file" do
      expect(action).to eq described_class::OPEN_FILE
    end

    it "resets the version" do
      expect(file1_state.version).to eq 1
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state OPEN" do
      expect(file1_state.state).to eq described_class::OPEN
    end
  end

  describe "closing an open file again" do
    let(:action) { file1_state.file_close_action }

    before do
      file1_state.dirty_file_action("test contents")
      file1_state.dirty_file_action("test contents changed")
      file1_state.dirty_file_action("test contents changed again")
      file1_state.dirty_file_action("test contents changed back")
      file1_state.file_close_action
      file1_state.dirty_file_action("test contents again 2")
      action
    end

    it "returns CLOSE_FILE" do
      expect(action).to eq described_class::CLOSE_FILE
    end

    it "has the same version as before" do
      expect(file1_state.version).to eq 1
    end

    it "has a checksum" do
      expect(file1_state.checksum).not_to be nil
    end

    it "has state CLOSED" do
      expect(file1_state.state).to eq described_class::CLOSED
    end
  end

  it "is able to remove a closed file" do
    expect { store.delete("file1") }.not_to raise_error
  end

  describe "replacing a deleted file" do
    let(:file1_again) { store["file1"] }
    let(:action) { file1_again.dirty_file_action("test contents again 3") }

    before do
      file1_state.dirty_file_action("test contents")
      file1_state.dirty_file_action("test contents changed")
      file1_state.dirty_file_action("test contents changed again")
      file1_state.dirty_file_action("test contents changed back")
      file1_state.file_close_action
      file1_state.dirty_file_action("test contents again 2")
      file1_state.file_close_action
      store.delete(file1_state.filename)
      action
    end

    it "opens the file again" do
      expect(action).to eq described_class::OPEN_FILE
    end

    it "resets the version to 1" do
      expect(file1_again.version).to eq 1
    end

    it "has a checksum" do
      expect(file1_again.checksum).not_to be nil
    end

    it "has state OPEN" do
      expect(file1_again.state).to eq described_class::OPEN
    end

    it "deleting an open file does not raise an error" do
      expect { store.delete(file1_again.filename) }.not_to raise_error
    end
  end

  describe "closing a closed file" do
    before do
      file1_state.dirty_file_action("test contents")
      file1_state.dirty_file_action("test contents changed")
      file1_state.dirty_file_action("test contents changed again")
      file1_state.dirty_file_action("test contents changed back")
      file1_state.file_close_action
    end

    it "returns NO_ACTION" do
      expect(file1_state.file_close_action).to eq described_class::NO_ACTION
    end
  end
end
