# frozen_string_literal: true

RSpec.describe ClangdClient do
  it "has a version number" do
    expect(ClangdClient::VERSION).not_to be nil
  end
end
