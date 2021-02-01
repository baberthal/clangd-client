# frozen_string_literal: true

RSpec.describe LanguageServer::Protocol do
  describe ".uri_to_file_path" do
    context "when on unix", if: ClangdClient.unix? do
      it "raises InvalidURIError if the args are malformed" do
        expect { described_class.uri_to_file_path("test") }
          .to raise_error LanguageServer::Protocol::InvalidURIError
      end

      it "properly parses the uri with a file:/ uri" do
        expect(
          described_class.uri_to_file_path("file:/usr/local/test/test.test")
        ).to eq "/usr/local/test/test.test"
      end

      it "properly parses the uri with a file:/// uri" do
        expect(
          described_class.uri_to_file_path("file:///usr/local/test/test.test")
        ).to eq "/usr/local/test/test.test"
      end
    end

    context "when on windows", if: ClangdClient.windows? do
      pending "Add some windows examples"
    end
  end

  describe ".file_path_to_uri" do
    it "properly creates a uri" do
      expect(
        described_class.file_path_to_uri("/usr/local/test/test.test")
      ).to eq "file:///usr/local/test/test.test"
    end
  end
end
