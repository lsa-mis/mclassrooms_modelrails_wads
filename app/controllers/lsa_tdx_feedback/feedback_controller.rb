module LsaTdxFeedback
  # Fork override of the gem's engine controller. Rails serves this app-side
  # class in place of the gem's `LsaTdxFeedback::FeedbackController` (host
  # autoload paths win over an engine's), so the modal's POST to
  # /lsa_tdx_feedback/feedback lands here.
  #
  # The gem's original hard-requires TDX config, has no email fallback, gates
  # nothing, and rate-limits nothing. We instead:
  #   - ALLOW UNAUTHENTICATED submissions — the person who can't sign in must
  #     still be able to report that they can't sign in;
  #   - rate-limit by IP (burst + sustained) so the open endpoint can't be
  #     flooded — Solid-Cache-backed, no Redis;
  #   - route through Feedback::Submit, which files a TDX ticket or falls back
  #     to emailing the directory's admins so feedback is never lost.
  #
  # Contract with the gem's modal JS: it POSTs
  #   { feedback: { category, feedback, email, url, user_agent, additional_info } }
  # and reads back { success:, message: } — honored exactly below.
  #
  # Upstream target (lsa-mis/lsa_feedback): land `require_authentication` (default
  # on), `rate_limit`, and a submission `fallback` hook as gem configuration so
  # any consumer gets this posture without overriding the controller.
  class FeedbackController < ::ApplicationController
    allow_unauthenticated_access only: :create

    # Resume the session when a valid cookie is present, so a signed-in
    # submitter's email prefills/falls back. allow_unauthenticated_access skips
    # require_authentication (which normally resumes it), so we do it here —
    # best-effort: nil for an anonymous visitor, never a sign-in challenge.
    before_action :resume_session, only: :create

    rate_limit to: 5, within: 1.minute,
               name: "feedback-burst",
               with: -> { render_rate_limited }, only: :create
    rate_limit to: 30, within: 1.hour,
               name: "feedback-sustained",
               with: -> { render_rate_limited }, only: :create

    def create
      authorize :feedback, :create?

      if feedback_params[:feedback].blank?
        return render json: { success: false, message: t("feedback.errors.blank_message") },
                      status: :unprocessable_entity
      end

      # Signed-in submitters always carry an email (the field is prefilled but
      # editable — a cleared field falls back to their account address);
      # anonymous submitters must supply one (the modal marks it required).
      email = feedback_params[:email].presence || Current.user&.email_address

      result = Feedback::Submit.call(
        message: feedback_params[:feedback],
        email: email,
        category: feedback_params[:category].presence,
        url: feedback_params[:url].presence,
        user_agent: feedback_params[:user_agent].presence,
        additional_info: feedback_params[:additional_info].presence
      )

      if result.success?
        render json: { success: true, message: t("feedback.flash.submitted"),
                       ticket_id: result.payload[:ticket_id] }, status: :created
      else
        render json: { success: false, message: t("feedback.flash.retry") },
               status: :unprocessable_entity
      end
    end

    private

    def feedback_params
      params.require(:feedback)
            .permit(:feedback, :category, :email, :url, :user_agent, :additional_info)
    end

    def render_rate_limited
      render json: { success: false, message: t("feedback.flash.rate_limited") },
             status: :too_many_requests
    end
  end
end
