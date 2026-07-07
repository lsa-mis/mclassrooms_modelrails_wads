# Non-production test login for accessibility crawlers (MiClassrooms Phase 0
# Task 8): Siteimprove can't complete Google/Okta SSO, so this backdoor signs
# a fixed test user in directly. This is a backdoor BY DESIGN — its safety
# rests on three independent defenses, each pinned by its own spec
# (spec/requests/test_login_spec.rb, spec/lib/auth_config_spec.rb):
#
#   1. Non-production only — AuthConfig.test_login_enabled? gates whether
#      config/routes/app.rb draws this route AT ALL, so in production the
#      route is structurally absent, not merely guarded.
#   2. A configured token must be present — re-checked here at request time
#      (not just at boot, when the route was drawn), so a token that goes
#      missing after boot still fails closed instead of raising.
#   3. Constant-time comparison — ActiveSupport::SecurityUtils.secure_compare
#      against the configured token, so a timing side-channel can't leak it.
class TestLoginsController < ApplicationController
  allow_unauthenticated_access

  TEST_LOGIN_EMAIL = "test-login@umich.edu"

  def create
    raise ActionController::RoutingError, "Not Found" unless valid_token?

    user = find_or_create_test_user

    grant_test_role(user)
    start_new_session_for(user)
    redirect_to root_path
  end

  private

  # find_or_create_by! is find-then-create, not atomic: concurrent crawler
  # requests can both miss the find and race the INSERT (unique index on
  # email_address makes the loser raise RecordNotUnique instead of a
  # duplicate row). Same shape as Role.system_default! (app/models/role.rb)
  # — rescue and re-find the winner's row.
  def find_or_create_test_user
    User.find_or_create_by!(email_address: TEST_LOGIN_EMAIL) do |u|
      u.first_name = "Siteimprove"
      u.last_name = "Crawler"
    end
  rescue ActiveRecord::RecordNotUnique
    User.find_by!(email_address: TEST_LOGIN_EMAIL)
  end

  def valid_token?
    configured_token = AuthConfig.test_login_token
    return false if configured_token.blank?

    ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, configured_token)
  end

  # Ensures the test user's membership (arrived via User#onboard_workspace,
  # the same callback every real sign-up goes through) matches
  # TEST_LOGIN_ADMIN — Admin when set to "true", Viewer otherwise — on every
  # login, so flipping the env var and logging in again both upgrades and
  # downgrades idempotently. A no-op under the :none tenancy posture, where
  # onboarding grants no membership at all.
  def grant_test_role(user)
    membership = user.memberships.first
    return unless membership

    desired_role = Role.system_default!(AuthConfig.test_login_admin? ? "admin" : "viewer")
    membership.update!(role: desired_role) unless membership.role_id == desired_role.id
  end
end
