# Posture-gated first-run guard. Under WORKSPACE_ON_SIGNUP=none, a signed-in
# user who has not finished onboarding is funneled into the wizard. Inert in
# every other posture, so the :personal/:shared flows and the zero-workspace
# crash-safety spec are unaffected. Controllers that must stay reachable mid-
# onboarding (the wizard itself, sign-out, email verification/resend) opt out
# via `skip_onboarding_requirement`.
module RequiresOnboarding
  extend ActiveSupport::Concern

  included do
    before_action :require_onboarding
  end

  class_methods do
    def skip_onboarding_requirement(**options)
      skip_before_action :require_onboarding, **options
    end
  end

  private

  def require_onboarding
    return unless TenancyConfig.none?
    return unless Current.user && !Current.user.onboarded?
    # Only funnel page navigations. Background XHR/JSON requests (e.g. the
    # timezone beacon PATCH fired by the layout Stimulus controller) must pass
    # through — redirect_to preserves the HTTP method, so a PATCH redirect into
    # OnboardingsController#update would prematurely mark the user onboarded.
    return unless request.format.html?

    redirect_to onboarding_path
  end
end
