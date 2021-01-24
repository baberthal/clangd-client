# frozen_string_literal: true

RSpec.describe ClangdClient::Version do
  let(:version10) { described_class.new(10, 0, 0) }
  let(:version11) { described_class.new(11, 0, 0) }
  let(:version10_1) { described_class.new(10, 1, 0) }
  let(:version11_1) { described_class.new(11, 1, 0) }

  describe ".parse" do
    let(:v) { described_class.parse("11.0.1") }

    it "parses the major version from a string" do
      expect(v.major).to eq 11
    end

    it "parses the minor version from a string" do
      expect(v.minor).to eq 0
    end

    it "parses the patch version from a string" do
      expect(v.patch).to eq 1
    end
  end

  describe "#==" do
    it "returns true if the versions are equal" do
      v1 = described_class.new(11, 0, 0)
      v2 = described_class.new(11, 0, 0)
      expect(v1).to eq v2
    end
  end

  describe "#<" do
    it "properly compares the version numbers" do
      expect(version10).to be < version11
    end
  end

  describe "#[]" do
    it "provides array-index like access" do
      expect(version10[0]).to eq 10
    end
  end

  describe "#to_a" do
    it "returns an array containing major,minor,patch versions" do
      ary = version10.to_a
      expect(ary).to eq [10, 0, 0]
    end
  end

  describe "#to_s" do
    it "returns a string representative of the version" do
      expect(version10.to_s).to eq "10.0.0"
    end
  end
end
