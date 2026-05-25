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
  # and the browser follows the redirect to new_registration_path, so the next
  # visit sees signups_open? == true.
  #
  # The GET accept page shows a "Create an account to accept" GET link for
  # unauthenticated visitors — clicking it bypasses the token stash. The actual
  # token stash happens only on POST (invitation_accepts#create). We submit a
  # hidden form via execute_script so the browser follows the 302 redirect,
  # landing on new_registration_path with the session set.
  def post_accept_invitation(token)
    # Load the accept page to seed the CSRF token into the browser session.
    visit accept_invitation_path(token: token)

    # Build and submit a hidden form that POSTs to the current URL. The browser
    # follows the redirect automatically, ending up at new_registration_path.
    # No authenticity_token needed: allow_forgery_protection is false in test env.
    page.execute_script(<<~JS)
      const form = document.createElement("form");
      form.method = "POST";
      form.action  = window.location.href;
      document.body.appendChild(form);
      form.submit();
    JS

    # Wait for the redirect to land before continuing.
    expect(page).to have_current_path(new_registration_path, wait: 5)
  end

  scenario "invited user signs up successfully" do
    invitation = create(:invitation, email: "newuser@example.com")
    workspace  = invitation.invitable

    # Stash the pending_invitation_token in the browser session via POST.
    post_accept_invitation(invitation.token)

    # Now visit the registration form — signups_open? should return true because
    # session[:pending_invitation_token] is present and the invitation is acceptable.
    visit new_registration_path

    expect(page).not_to have_text(I18n.t("registrations.closed.title"))
    expect(page).to have_field(I18n.t("registrations.new.email_label"))

    fill_in I18n.t("registrations.new.email_label"),              with: "newuser@example.com"
    fill_in I18n.t("registrations.new.first_name_label"),         with: "Invited"
    fill_in I18n.t("registrations.new.last_name_label"),          with: "User"
    fill_in I18n.t("registrations.new.password_label"),           with: "SecureP@ssw0rd123!"
    fill_in I18n.t("registrations.new.password_confirmation_label"), with: "SecureP@ssw0rd123!"

    click_button I18n.t("registrations.new.submit")

    # Successful registration redirects to root.
    expect(page).to have_current_path(root_path)

    # Verify the invitation was consumed.
    expect(invitation.reload).to be_accepted

    # Verify workspace membership was created.
    new_user = User.find_by(email_address: "newuser@example.com")
    expect(new_user).to be_present
    expect(new_user.workspaces).to include(workspace)
  end

  scenario "uninvited visitor sees the closed page on /registration/new" do
    visit new_registration_path

    expect(page).to have_text(I18n.t("registrations.closed.title"))
    expect(page).to have_link(
      I18n.t("registrations.closed.sign_in_link"),
      href: new_session_path
    )
  end

  scenario "closed page passes axe-core AAA accessibility scan (light + dark)" do
    axe_options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }

    visit new_registration_path

    expect(page).to have_text(I18n.t("registrations.closed.title"))

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
