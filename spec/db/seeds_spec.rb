require "rails_helper"

# Exercises the :shared (Single-tenant) bootstrap branch of db/seeds.rb. The
# production branch must tell the operator where the workspace lives and how to
# get a sign-in link — but it must NOT embed a live password credential in the
# logs (log retention/aggregation outlives a 15-minute token). It points at the
# on-demand `tenancy:owner_setup_link` task instead.
RSpec.describe "db/seeds.rb :shared bootstrap", type: :request do
  let(:env_vars) do
    {
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
    allow(TenancyConfig).to receive(:shared_workspace_slug).and_return("acme")
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
      # SEC-5: only the digest is stored — the plaintext exists solely in the
      # emailed URL. Extract it from the body and verify it digests to the row.
      plaintext = mail.body.encoded[%r{magic_link_callback/([A-Za-z0-9_-]+)}, 1]
      expect(plaintext).to be_present
      expect(MagicLinkToken.digest(plaintext)).to eq(token.token_digest)
    end
  end

  it "grants the bootstrap owner an operatorship, idempotently" do
    allow(Rails.logger).to receive(:info)

    Rails.application.load_seed
    Rails.application.load_seed

    owner = User.find_by!(email_address: "owner@acme.test")
    expect(owner).to be_operator
    expect(owner.operatorships.kept.count).to eq(1)
  end

  it "does not resurrect a bootstrap owner's operatorship after it was revoked" do
    allow(Rails.logger).to receive(:info)

    Rails.application.load_seed
    owner = User.find_by!(email_address: "owner@acme.test")
    owner.operatorships.kept.sole.revoke!

    Rails.application.load_seed

    expect(owner.reload).not_to be_operator
  end

  context "naming the shared workspace" do
    before { allow(Rails.logger).to receive(:info) }

    def stub_brand_name(&answer)
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t).with("application.name", any_args, &answer)
    end

    context "without TENANCY_SHARED_WORKSPACE_NAME" do
      let(:env_vars) { super().merge("TENANCY_SHARED_WORKSPACE_NAME" => nil) }

      it "names the shared workspace after the brand" do
        stub_brand_name { "Acme Garden" }

        Rails.application.load_seed

        expect(Workspace.find_by!(slug: "acme").name).to eq("Acme Garden")
      end

      it "falls back to the slug when the brand has no name" do
        stub_brand_name { |_key, **options| options[:default] }

        Rails.application.load_seed

        expect(Workspace.find_by!(slug: "acme").name).to eq("Acme")
      end
    end

    it "lets TENANCY_SHARED_WORKSPACE_NAME override the brand" do
      stub_brand_name { "Acme Garden" }

      Rails.application.load_seed

      expect(Workspace.find_by!(slug: "acme").name).to eq("Acme Inc")
    end
  end

  context "without TENANCY_OWNER_EMAIL" do
    let(:env_vars) { super().merge("TENANCY_OWNER_EMAIL" => nil) }

    it "refuses to seed production without the owner it names" do
      expect { Rails.application.load_seed }.to raise_error(/TENANCY_OWNER_EMAIL is required/)
    end

    it "seeds a fresh fork's development database with a placeholder owner to claim from letter_opener" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      allow(TenancyConfig).to receive(:shared_workspace_slug).and_return("acme_garden")
      ActionMailer::Base.deliveries.clear

      Rails.application.load_seed

      expect(Workspace.find_by!(slug: "acme_garden").memberships.sole.user.email_address).to eq("owner@acme-garden.test")
      expect(ActionMailer::Base.deliveries.sole.to).to eq([ "owner@acme-garden.test" ])
    end
  end

  context "outside production" do
    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      ActionMailer::Base.deliveries.clear
    end

    context "when sign-up onboards into the shared workspace" do
      before do
        allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
        allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return("acme")
      end

      it "seats the bootstrap owner as Owner without announcing a role change", :aggregate_failures do
        perform_enqueued_jobs { Rails.application.load_seed }

        membership = Workspace.find_by!(slug: "acme").memberships.sole
        expect(membership.role.slug).to eq("owner")
        expect(Noticed::Event.where(type: "WorkspaceRoleChangedNotifier")).to be_none
        expect(ActionMailer::Base.deliveries.map(&:subject)).to eq([ I18n.t("magic_link_mailer.sign_in_link.subject") ])
      end
    end

    it "emails the bootstrap owner a set-password sign-in link" do
      Rails.application.load_seed

      mail = ActionMailer::Base.deliveries.sole
      expect(mail.to).to eq([ "owner@acme.test" ])
      token = mail.body.encoded[%r{/magic_link_callback/([\w-]+)}, 1]
      expect(MagicLinkToken.find_by!(token_digest: MagicLinkToken.digest(token)).intent).to eq("set_password")
    end
  end
end
