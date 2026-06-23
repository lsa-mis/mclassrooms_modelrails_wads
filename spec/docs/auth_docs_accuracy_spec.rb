require "rails_helper"

RSpec.describe "Auth docs accuracy", type: :model do
  DOCS = Rails.root.join("app/docs")

  # Guards the specific code IDENTIFIERS deleted in Phase A (password_reset_email,
  # password_reset_token, AuthenticationMailer password-reset variant) — not every
  # prose occurrence of "password reset". Do NOT loosen this to /password.reset/i:
  # that would false-positive on the still-accurate "POST /passwords (reset)" rate-limit
  # row in security.md and the Password Reset section in accounts.md.
  it "has no references to the removed password-reset mailer/token" do
    offenders = Dir[DOCS.join("*.md")].select do |f|
      File.read(f).match?(/password_reset_email|password_reset_token|AuthenticationMailer[^\n]*password reset/i)
    end
    expect(offenders).to be_empty, "stale password-reset refs in: #{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  # The flows page must not depict a password field at signup/invite (passwordless-first).
  it "the flows page does not show a Create/Set password field" do
    flows = File.read(DOCS.join("application-flows.md"))
    expect(flows).not_to match(/Create password|Set a password|>Password<|Password<\/text>/)
  end
end
