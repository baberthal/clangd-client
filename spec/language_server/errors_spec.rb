# frozen_string_literal: true

RSpec.describe LanguageServer::Protocol::Errors do
  describe ".create" do
    let(:eklass) { described_class.create(27, "Failed") }

    it "returns a class" do
      expect(eklass).to be_a Class
    end

    it "returns a class with a class method .code" do
      expect(eklass.code).to eq 27
    end

    it "returns a class with a class method .reason" do
      expect(eklass.reason).to eq "Failed"
    end

    it "returns a class with an instance method #code" do
      instance = eklass.new
      expect(instance.code).to eq 27
    end

    it "returns a class with an instance method #reason" do
      instance = eklass.new
      expect(instance.reason).to eq "Failed"
    end
  end

  describe ".lookup" do
    it "returns the corresponding error class, if it exists" do
      expect(described_class.lookup(:RequestCancelled)).to \
        eq described_class::RequestCancelled
    end

    it "raises if the error is not known" do
      expect { described_class.lookup(:NotAnError) }
        .to raise_error NameError, /Unknown error/
    end
  end
end
