require "rails_helper"

RSpec.describe "Passwordless join-link signup", type: :system do
  # Permit :open_link at the instance level (SignupPolicy) and allow the workspace
  # factory to set join_policy: :open_link (validates join_policy_must_be_permitted_by_instance).
  # Use direct config mutation (not allow stubs) so the value is visible on the Rack
  # server thread that handles browser requests from the Playwright driver.
  before do
    # Capture originals BEFORE mutating. A lazy `let` referenced only from `after`
    # evaluates AFTER these assignments — capturing :open as the "original" and
    # making the restore a no-op, which leaks signup mode into later specs under
    # random ordering. Capture into ivars here instead (cf. passwordless_auth_spec).
    @original_strategies = Rails.configuration.x.signup.permitted_join_strategies
    @original_mode = Rails.configuration.x.signup.mode
    Rails.configuration.x.signup.permitted_join_strategies = [ :invite, :open_link ]
    Rails.configuration.x.signup.mode = :open
    # default_self_join_role calls Role.find_by!(slug: "member", workspace_id: nil) — ensure it exists.
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
  end

  after do
    Rails.configuration.x.signup.permitted_join_strategies = @original_strategies
    Rails.configuration.x.signup.mode = @original_mode
  end

  let(:join_workspace) { create(:workspace, join_policy: :open_link) }
  let(:join_link) { create(:workspace_join_link, workspace: join_workspace) }

  # Shared helper: visit the join confirmation page and POST the join form so that
  # session[:pending_join_token] is set on the server-side session (cookie store).
  # button_to triggers a Turbo form submission (TURBO_STREAM); using execute_script
  # for a native browser form POST ensures the browser follows the 302 redirect
  # and stores the session cookie for all subsequent requests in this Playwright
  # session — the same pattern used by invite_only_signup_spec.
  def confirm_join_link
    visit workspace_join_path(join_workspace, token: join_link.token)

    # Native form POST via execute_script bypasses Turbo's fetch-based submission.
    # forgery_protection is disabled in test env, so no CSRF token needed.
    page.execute_script(<<~JS)
      const form = document.createElement("form");
      form.method = "POST";
      form.action  = window.location.href;
      document.body.appendChild(form);
      form.submit();
    JS

    # Wait for the redirect to new_session_path before continuing.
    expect(page).to have_current_path(new_session_path, wait: 5)
  end

  # Shared helper: navigate to the session entry page, enter email to request a
  # magic link, then complete signup via the token extracted from the database.
  def complete_magic_link_signup(email:, first_name:, last_name:)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: email
    click_button I18n.t("sessions.new.continue")

    expect(page).to have_text(I18n.t("sessions.check_email.title"))

    token_record = MagicLinkToken.where(email: email).order(:created_at).last
    visit magic_link_callback_path(token: token_record.token)

    fill_in I18n.t("magic_link_callbacks.new_registration.first_name_label"), with: first_name
    fill_in I18n.t("magic_link_callbacks.new_registration.last_name_label"), with: last_name
    click_button I18n.t("magic_link_callbacks.new_registration.submit")
    # Wait for the redirect to complete so DB writes are committed before find_by.
    expect(page).to have_text(I18n.t("magic_link_callbacks.create.registered"))
  end

  describe "happy path: brand-new user lands on open join link then signs up via magic link" do
    it "admits the user as a member of the workspace" do
      # 1. Visit the join confirmation page and confirm — stashes token in session.
      confirm_join_link

      # 2. Navigate to the sign-in / session entry to request a magic link.
      #    session[:pending_join_token] persists across this navigation.
      complete_magic_link_signup(
        email: "joiner@example.com",
        first_name: "Jo",
        last_name: "Iner"
      )

      # 3. Assert DB state: user created AND membership kept.
      user = User.find_by(email_address: "joiner@example.com")
      expect(user).to be_present
      expect(user.memberships.kept.where(workspace: join_workspace)).to exist
    end
  end

  describe "stale/closed-link no-op: link is revoked before signup completes" do
    it "signs the user up successfully but does NOT grant workspace membership" do
      # 1. Confirm the join link — stashes token.
      confirm_join_link

      # 2. Revoke the link BEFORE the user finishes signup.
      join_link.update!(revoked_at: Time.current)

      # 3. Proceed through magic-link signup. No error should be raised.
      complete_magic_link_signup(
        email: "latecomer@example.com",
        first_name: "Late",
        last_name: "Comer"
      )

      # 4. Account is created.
      user = User.find_by(email_address: "latecomer@example.com")
      expect(user).to be_present

      # 5. No membership — silent no-op branch in accept_pending_join_link!.
      expect(user.memberships.kept.where(workspace: join_workspace)).not_to exist
    end
  end

  describe "stale/closed-link no-op: workspace join policy reverted before signup completes" do
    it "signs the user up successfully but does NOT grant workspace membership" do
      # 1. Confirm the join link — stashes token.
      confirm_join_link

      # 2. Revert workspace to invite-only BEFORE signup finishes (open_join? → false).
      join_workspace.update_column(:join_policy, :invite_only)

      # 3. Proceed through magic-link signup. No error should be raised.
      complete_magic_link_signup(
        email: "tooslow@example.com",
        first_name: "Too",
        last_name: "Slow"
      )

      # 4. Account is created — signup succeeded despite policy change.
      user = User.find_by(email_address: "tooslow@example.com")
      expect(user).to be_present

      # 5. No membership — open_join? returned false, silent no-op branch taken.
      expect(user.memberships.kept.where(workspace: join_workspace)).not_to exist
    end
  end
end
