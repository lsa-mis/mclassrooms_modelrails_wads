require "rails_helper"

# Exercises the :shared (Single-tenant) bootstrap branch of db/seeds.rb. The
# production branch must tell the operator where the workspace lives and how to
# get a sign-in link — but it must NOT embed a live password credential in the
# logs (log retention/aggregation outlives a 15-minute token). It points at the
# on-demand `tenancy:owner_setup_link` task instead.
RSpec.describe "db/seeds.rb :shared bootstrap", type: :request do
  let(:env_vars) do
    {
      "TENANCY_SHARED_WORKSPACE_SLUG" => "acme",
      "TENANCY_SHARED_WORKSPACE_NAME" => "Acme Inc",
      "TENANCY_OWNER_EMAIL" => "owner@acme.test",
      "APP_HOST" => "acme.example.com"
    }
  end

  around do |example|
    originals = env_vars.transform_values { |_| :__unset__ }
    env_vars.each { |k, v| originals[k] = ENV[k]; ENV[k] = v }
    example.run
    originals.each { |k, v| v == :__unset__ ? ENV.delete(k) : ENV[k] = v }
  end

  before do
    allow(TenancyConfig).to receive(:shared?).and_return(true)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
  end

  it "logs the workspace URL and points to the setup-link task, without embedding a credential" do
    logged = []
    allow(Rails.logger).to receive(:info) { |msg| logged << msg }

    Rails.application.load_seed

    tenancy_line = logged.find { |m| m.to_s.include?("[tenancy]") }
    expect(tenancy_line).to be_present
    expect(tenancy_line).to include("/workspaces/acme")           # operator's destination
    expect(tenancy_line).to include("tenancy:owner_setup_link")   # on-demand mint, not a logged token
    expect(tenancy_line).not_to include("/passwords/")            # no live password credential in logs
  end

  # MiClassrooms Task 4 bug fix: outside production the seed used to call
  # AuthenticationMailer.password_reset_email, a method that does not exist in
  # this codebase's passwordless-first mailers — a NoMethodError on every
  # db:seed run under :shared in dev/test. Only the production branch above
  # was ever covered, so this went undetected. Locks in the fix: the seed now
  # mints a MagicLinkToken (intent: "set_password") and sends it via
  # MagicLinkMailer#sign_in_link, the same mechanism
  # PasswordResetsController#create and `tenancy:owner_setup_link` use.
  context "outside production" do
    before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test")) }

    it "sends a magic-link password-set email instead of raising" do
      expect { Rails.application.load_seed }
        .to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to include("owner@acme.test")

      owner = User.find_by!(email_address: "owner@acme.test")
      token = MagicLinkToken.where(email: owner.email_address, intent: "set_password").order(:created_at).last
      expect(token).to be_present
      expect(mail.body.encoded).to include(token.token)
    end
  end
end
