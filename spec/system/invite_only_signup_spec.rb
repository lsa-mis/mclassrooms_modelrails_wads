# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Invite-only signup flow", type: :system do
  # Default SIGNUP_MODE in application.rb is :invite_only — no stub needed,
  # but we make it explicit so this spec is self-documenting and safe if the
  # default ever changes.
  before do
    allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
  end

  # Helper: trigger POST /invitations/:token/accept within the running Playwright
  # browser session. This stashes pending_invitation_token in the Rails session
  # and the browser follows the redirect to new_session_path (the magic-link entry
  # point), so the next visit sees signups_open? == true.
  #
  # The actual token stash happens only on POST (invitation_accepts#create). We
  # submit a hidden form via execute_script so the browser follows the 303 redirect,
  # landing on new_session_path with the session set.
  def post_accept_invitation(token)
    # Load the accept page to seed the CSRF token into the browser session.
    visit accept_invitation_path(token: token)

    # Build and submit a hidden form that POSTs to the current URL. The browser
    # follows the redirect automatically, ending up at new_session_path.
    # No authenticity_token needed: allow_forgery_protection is false in test env.
    page.execute_script(<<~JS)
      const form = document.createElement("form");
      form.method = "POST";
      form.action  = window.location.href;
      document.body.appendChild(form);
      form.submit();
    JS

    # Wait for the redirect to land before continuing.
    expect(page).to have_current_path(new_session_path, wait: 5)
  end

  scenario "invited user signs up via magic-link, then joins the workspace" do
    invitation = create(:invitation, email: "newuser@example.com")
    workspace  = invitation.invitable

    # Stash the pending_invitation_token in the browser session via POST.
    post_accept_invitation(invitation.token)

    # Now on sessions/new — enter email to request magic link.
    expect(page).to have_field(I18n.t("sessions.new.email_label"))
    fill_in I18n.t("sessions.new.email_label"), with: "newuser@example.com"
    click_button I18n.t("sessions.new.continue")

    expect(page).to have_text(I18n.t("sessions.check_email.title"))

    # Extract the magic-link token from the database and visit the callback.
    token_record = MagicLinkToken.where(email: "newuser@example.com").order(:created_at).last
    visit magic_link_callback_path(token: token_record.token)

    # New-user registration form: fill in name and submit.
    fill_in I18n.t("magic_link_callbacks.new_registration.first_name_label"), with: "Invited"
    fill_in I18n.t("magic_link_callbacks.new_registration.last_name_label"),  with: "User"
    click_button I18n.t("magic_link_callbacks.new_registration.submit")

    expect(page).to have_text(I18n.t("magic_link_callbacks.create.registered"))

    new_user = User.find_by(email_address: "newuser@example.com")
    expect(new_user).to be_present

    # Magic-link signup is atomic: invitation accepted immediately.
    expect(invitation.reload).to be_accepted
    expect(new_user.workspaces).to include(workspace)
  end

  scenario "uninvited visitor is sent to sign-in (no separate closed page)" do
    visit new_session_path

    # sessions#new is always accessible — it's both sign-in AND signup entry.
    # No 'closed' state; signups_open? gates the magic-link flow server-side.
    expect(page).to have_field(I18n.t("sessions.new.email_label"))
    expect(page).not_to have_text(I18n.t("registrations.closed.title"))
  end

  scenario "invited user signs up via OAuth (mocked Google)" do
    invitation = create(:invitation,
                        email: "oauthinvitee@example.com")
    workspace  = invitation.invitable

    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "sys-spec-uid-oauth",
      info: {
        email: "oauthinvitee@example.com",
        first_name: "OAuth",
        last_name: "Invitee",
        email_verified: true
      },
      credentials: { token: "tk", refresh_token: "rt", expires_at: 1.hour.from_now.to_i }
    )

    # oauth_enabled? gates the button rendering. enabled_oauth_providers filters
    # PROVIDER_CONFIG by which providers have a client_id in credentials
    # (OauthHelper#enabled_oauth_providers). Stub the SOURCE so the real helper
    # computes: google present, github absent -> only the Google button renders.
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:oauth, :google, :client_id).and_return("test-google-client-id")
    allow(Rails.application.credentials).to receive(:dig)
      .with(:oauth, :github, :client_id).and_return(nil)

    # Stash the invitation token in session; lands on new_session_path.
    post_accept_invitation(invitation.token)

    # Click the Google OAuth button — turbo is disabled on the form so the
    # browser performs a standard POST to /auth/google_oauth2.
    click_button I18n.t("oauth.sign_in_with", provider: "Google")

    # The OAuth callback completes the flow and redirects to root.
    expect(page).to have_current_path(root_path, wait: 10)

    new_user = User.find_by(email_address: "oauthinvitee@example.com")
    expect(new_user).to be_present
    expect(new_user.workspaces).to include(workspace)
    expect(invitation.reload).to be_accepted
  end
end
