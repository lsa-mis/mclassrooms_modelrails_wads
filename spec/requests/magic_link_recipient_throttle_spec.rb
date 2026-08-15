# frozen_string_literal: true

require "rails_helper"

# SEC-9: the four magic-link send endpoints were rate-limited per-IP only, and
# MagicLinkToken.create_for_email supersedes every outstanding token for the
# email (intent-blind) — so an attacker rotating IPs could invalidate the link
# a victim was mid-click on, indefinitely (denial-of-login).
#
# The recipient throttle closes this two ways: it caps sends per RECIPIENT
# regardless of source IP, and — the load-bearing part — a throttled request
# skips create_for_email entirely, so it cannot supersede the victim's
# outstanding link. Responses are identical throttled or not (no leakage).
RSpec.describe "Magic-link recipient throttle (SEC-9)", type: :request do
  include ActiveJob::TestHelper

  # Test env uses :null_store (fail-open throttle); swap in a real store.
  around do |ex|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ex.run
  ensure
    Rails.cache = original
  end

  let(:user) { create(:user) }
  let(:cap) { EmailRecipientThrottle::KIND_POLICIES.fetch(:magic_link)[:cap] }

  def exhaust_cap(email)
    cap.times { EmailRecipientThrottle.allow!(email, kind: :magic_link) }
  end

  describe "POST /session/lookup (sign-in branch)" do
    it "sends normally under the cap" do
      expect {
        post session_lookup_path, params: { email_address: user.email_address }
      }.to change { MagicLinkToken.count }.by(1)
      expect(response.body).to include(CGI.escapeHTML(user.email_address))
    end

    it "renders check_email without minting a token or sending mail when throttled" do
      exhaust_cap(user.email_address)

      expect {
        expect {
          post session_lookup_path, params: { email_address: user.email_address }
        }.not_to change { MagicLinkToken.count }
      }.not_to have_enqueued_mail(MagicLinkMailer, :sign_in_link)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(user.email_address))
    end

    it "does not supersede the victim's outstanding link when throttled" do
      plaintext = MagicLinkToken.create_for_email(user.email_address)
      exhaust_cap(user.email_address)

      post session_lookup_path, params: { email_address: user.email_address }

      expect(MagicLinkToken.find_valid(plaintext)).to be_present
    end
  end

  describe "POST /session/lookup (registration branch)" do
    around do |ex|
      original = Rails.configuration.x.signup.mode
      Rails.configuration.x.signup.mode = :open
      ex.run
    ensure
      Rails.configuration.x.signup.mode = original
    end

    it "renders check_email without minting a token when throttled" do
      email = "newcomer@example.com"
      exhaust_cap(email)

      expect {
        post session_lookup_path, params: { email_address: email }
      }.not_to change { MagicLinkToken.count }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(email))
    end
  end

  describe "POST /magic_links (resend)" do
    it "redirects with the normal notice without minting a token when throttled" do
      exhaust_cap(user.email_address)

      expect {
        post magic_link_path, params: { email_address: user.email_address }
      }.not_to change { MagicLinkToken.count }

      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to eq(I18n.t("magic_links.create.check_email"))
    end

    it "does not supersede the outstanding link when throttled" do
      plaintext = MagicLinkToken.create_for_email(user.email_address)
      exhaust_cap(user.email_address)

      post magic_link_path, params: { email_address: user.email_address }

      expect(MagicLinkToken.find_valid(plaintext)).to be_present
    end
  end

  describe "POST /password_resets" do
    let(:user) { create(:user) } # factory users have a password

    it "renders the normal confirmation without minting a token when throttled" do
      exhaust_cap(user.email_address)

      expect {
        post password_reset_path, params: { email_address: user.email_address }
      }.not_to change { MagicLinkToken.count }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "shared bucket across endpoints" do
    it "counts sends from every magic-link endpoint against one recipient bucket" do
      # Burn the whole cap through lookup, then confirm the resend endpoint
      # is also throttled — endpoint-hopping must not reset the budget.
      cap.times { post session_lookup_path, params: { email_address: user.email_address } }

      expect {
        post magic_link_path, params: { email_address: user.email_address }
      }.not_to change { MagicLinkToken.count }
    end
  end
end
