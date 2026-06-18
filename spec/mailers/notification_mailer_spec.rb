require "rails_helper"

RSpec.describe NotificationMailer, type: :mailer do
  # WCAG 2.2 AAA — screen-reader and preview-pane skim:
  # The H1 in an HTML email must describe the email's PURPOSE, not the
  # recipient's name. Greetings live in a <p> below the H1. The text/plain
  # part should mirror the same heading-first ordering for parity.

  describe "#workspace_role_changed" do
    let(:user) { create(:user, email_address: "ada@example.com", first_name: "Ada") }
    let(:workspace) { create(:workspace, name: "Acme") }
    let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }
    let(:membership) { create(:membership, user: user, workspace: workspace, role: admin_role) }

    let(:mail) do
      described_class.with(
        notification: nil,
        recipient: user,
        record: membership
      ).workspace_role_changed
    end

    it "uses a localized purpose-driven H1, NOT the greeting" do
      html = mail.html_part.body.encoded
      heading = I18n.t("notification_mailer.workspace_role_changed.heading", workspace: "Acme")
      expect(html).to match(%r{<h1[^>]*>\s*#{Regexp.escape(heading)}\s*</h1>}m)
      # And the H1 must NOT be the greeting (recipient-name-first is wrong for skim).
      expect(html).not_to match(%r{<h1[^>]*>\s*Hi Ada,?\s*</h1>}m)
    end

    it "places the greeting in a <p> below the H1" do
      html = mail.html_part.body.encoded
      h1_index = html.index("<h1")
      greeting_index = html.index("Hi Ada")
      expect(h1_index).to be_present
      expect(greeting_index).to be_present
      expect(greeting_index).to be > h1_index
    end
  end

  describe "#workspace_invitation_expiring_soon" do
    let(:workspace) { create(:workspace, name: "Globex") }
    let(:inviter) { create(:user) }
    let(:user) { create(:user, email_address: "grace@example.com", first_name: "Grace") }
    let(:invitation) do
      create(:invitation,
             invitable: workspace,
             email: user.email_address,
             invited_by: inviter,
             expires_at: 24.hours.from_now)
    end

    let(:mail) do
      described_class.with(
        notification: nil,
        recipient: user,
        record: invitation
      ).workspace_invitation_expiring_soon
    end

    it "uses a localized purpose-driven H1, NOT the greeting" do
      html = mail.html_part.body.encoded
      heading = I18n.t("notification_mailer.workspace_invitation_expiring_soon.heading", workspace: "Globex")
      expect(html).to match(%r{<h1[^>]*>\s*#{Regexp.escape(heading)}\s*</h1>}m)
      expect(html).not_to match(%r{<h1[^>]*>\s*Hi Grace,?\s*</h1>}m)
    end

    it "places the greeting in a <p> below the H1" do
      html = mail.html_part.body.encoded
      h1_index = html.index("<h1")
      greeting_index = html.index("Hi Grace")
      expect(h1_index).to be_present
      expect(greeting_index).to be_present
      expect(greeting_index).to be > h1_index
    end
  end

  describe "#sign_in_from_new_device" do
    # Use a real cache store so EmailRecipientThrottle's increment counts.
    around do |ex|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      ex.run
    ensure
      Rails.cache = original
    end

    let(:user) { create(:user, email_address: "ada@example.com", first_name: "Ada") }
    # Build a Noticed::Event so params[:notification].params[:os] resolves.
    let(:notification) do
      SignInFromNewDeviceNotifier.new(
        params: { user_agent: "Mozilla/5.0", os: "Macintosh" }
      )
    end

    let(:mail) do
      described_class.with(
        notification: notification,
        recipient: user,
        record: user
      ).sign_in_from_new_device
    end

    it "addresses the user's email address" do
      expect(mail.to).to eq([ "ada@example.com" ])
    end

    it "subject substitutes the OS" do
      expect(mail.subject).to eq(
        I18n.t("notification_mailer.sign_in_from_new_device.subject", os: "Macintosh")
      )
    end

    it "uses a localized purpose-driven H1, NOT the greeting" do
      html = mail.html_part.body.encoded
      heading = I18n.t("notification_mailer.sign_in_from_new_device.heading")
      expect(html).to match(%r{<h1[^>]*>\s*#{Regexp.escape(heading)}\s*</h1>}m)
      expect(html).not_to match(%r{<h1[^>]*>\s*Hi Ada,?\s*</h1>}m)
    end

    it "places the greeting in a <p> below the H1" do
      html = mail.html_part.body.encoded
      h1_index = html.index("<h1")
      greeting_index = html.index("Hi Ada")
      expect(h1_index).to be_present
      expect(greeting_index).to be_present
      expect(greeting_index).to be > h1_index
    end

    it "renders the OS in the body" do
      expect(mail.html_part.body.encoded).to include("Macintosh")
      expect(mail.text_part.body.encoded).to include("Macintosh")
    end

    it "links to the connected accounts page" do
      expect(mail.html_part.body.encoded).to include(settings_connected_accounts_url)
      expect(mail.text_part.body.encoded).to include(settings_connected_accounts_url)
    end
  end
end
