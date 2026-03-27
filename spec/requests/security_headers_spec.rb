require "rails_helper"

RSpec.describe "Security headers" do
  it "includes Referrer-Policy" do
    get root_path
    expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
  end

  it "includes Permissions-Policy" do
    get root_path
    expect(response.headers["Permissions-Policy"]).to be_present
  end
end
