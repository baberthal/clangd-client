# frozen_string_literal: true

RSpec.describe LanguageServer::ProcessHandle do
  let(:cmd) { %w[echo hello] }
  let(:handle) { described_class.new(cmd, **options) }

  describe "initialization and parsing of options" do
    context "when stdin: PIPE is passed" do
      let(:options) { { stdin: described_class::PIPE } }

      it "sets spawn_options[:in] to a pipe" do
        expect(handle.spawn_options[:in]).to be_an IO
      end
    end

    context "when stdout: PIPE  is passed" do
      let(:options) { { stdout: described_class::PIPE } }

      it "sets spawn_options[:out] to a pipe" do
        expect(handle.spawn_options[:out]).to be_an IO
      end
    end

    context "when stderr: PIPE is passed" do
      let(:options) { { stderr: described_class::PIPE } }

      it "sets spawn_options[:err] to a pipe" do
        expect(handle.spawn_options[:err]).to be_an IO
      end
    end

    context "when both stderr: and stdout: are set to PIPE" do
      let(:options) do
        { stdout: described_class::PIPE, stderr: described_class::PIPE }
      end

      it "sets both spawn_options[:out] to a pipe" do
        expect(handle.spawn_options[:out]).to be_an IO
      end

      it "sets spawn_options[:err] to a pipe" do
        expect(handle.spawn_options[:err]).to be_an IO
      end
    end

    context "when stdout is a pipe and stderr is STDOUT" do
      let(:options) do
        { stdout: described_class::PIPE, stderr: described_class::STDOUT }
      end

      it "sets spawn_options[[:out, :err]] to a pipe" do
        expect(handle.spawn_options[%i[out err]]).to be_an IO
      end
    end
  end

  describe "#command" do
    it "sets the command attribute" do
      command = %w[echo all your base are belong to us]
      p = described_class.new(command, stdout: "/dev/null")
      expect(p.command).to eq command
      p.wait
    end
  end

  describe "#pid" do
    it "sets the pid after it has been called" do
      p = described_class.new(["true"])
      expect(p.pid).to be > 1
      p.wait
    end
  end

  it "closes all file descriptions after running" do
    pending "Not implemented"
  end
end
