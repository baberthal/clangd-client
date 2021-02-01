# frozen_string_literal: true

RSpec.describe LanguageServer::Utils do
  describe ".remove_if_exists" do
    let(:tempfile) { fixture("remove-if-exists") }

    context "when the specified file exists" do
      before do
        File.open(tempfile, "a").close
      end

      it "removes the file" do
        expect(File.exist?(tempfile)).to be true
        described_class.remove_if_exists(tempfile)
        expect(File.exist?(tempfile)).to be false
      end
    end

    context "when the specified file does not exist" do
      it "does nothing, and the file does not exist" do
        expect(File.exist?(tempfile)).to be false
        described_class.remove_if_exists(tempfile)
        expect(File.exist?(tempfile)).to be false
      end
    end
  end

  describe ".path_to_first_existing_executable" do
    it "finds the executable if it exists on the system" do
      exe = described_class.path_to_first_existing_executable(["cat"])
      expect(exe).not_to be nil
    end

    it "returns nil if the executable does not exist on the system" do
      exe = described_class.path_to_first_existing_executable(["not-an-exe"])
      expect(exe).to be nil
    end
  end

  describe ".paths_to_all_parent_folders" do
    pending "Not implemented"
  end

  describe ".open_for_std_handle" do
    let(:temp) { fixture("open-for-std-handle") }

    it "does not throw an error when writing to the file" do
      expect do
        described_class.open_for_std_handle(temp) do |f|
          f.write "foo"
        end
      end.not_to raise_error
    ensure
      File.unlink(temp)
    end
  end

  describe ".find_executable" do
    it "finds the exe with an absolute path" do
      temporary_executable do |executable|
        expect(executable).to eq described_class.find_executable(executable)
      end
    end

    it "finds the executable with a relative path" do
      temporary_executable do |executable|
        dirname, exename = File.split(executable)
        relative_executable = File.join(".", exename)
        Dir.chdir(dirname) do
          expect(described_class.find_executable(relative_executable)).to \
            eq relative_executable
        end
      end
    end

    context "when the executable name is in PATH" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("PATH").and_return(Dir.tmpdir)
      end

      it "finds the executable in PATH" do
        temporary_executable do |executable|
          dirname, exename = File.split(executable)
          expect(executable).to eq described_class.find_executable(exename)
        end
      end
    end

    it "returns nil if the file is not executable" do
      Tempfile.new do |non_executable|
        expect(described_class.find_executable(non_executable.path)).to be nil
      end
    end
  end

  describe ".wait_for_process_to_terminate" do
    before do
      allow(described_class).to receive(:process_running?).and_return(true)
    end

    it "raises a runtime error" do
      expect { described_class.wait_for_process_to_terminate(nil, timeout: 0) }
        .to raise_error RuntimeError, /Waited 0 seconds for process to terminate/
    end
  end

  describe ".safe_filename_string" do
    name_pairs = [
      ["this is a test 0123 -x", "this_is_a_test_0123__x"],
      ["This Is A Test 0123 -x", "this_is_a_test_0123__x"],
      ["T˙^ß ^ß å †´ß† 0123 -x", "t______________0123__x"],
      ["contains/slashes",       "contains_slashes"],
      ["contains/newline/\n",    "contains_newline__"],
      ["",                       ""]
    ]

    name_pairs.each do |pair|
      unsafe_name, safe_name = pair

      it "transforms '#{unsafe_name}' to '#{safe_name}'" do
        expect(described_class.safe_filename_string(unsafe_name)).to eq safe_name
      end
    end
  end
end
