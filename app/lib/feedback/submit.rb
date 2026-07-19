module Feedback
  # Orchestrates a feedback submission (Phase 8 Task 1). Primary path: create a
  # TeamDynamix ticket through LSA's lsa_tdx_feedback gem
  # (LsaTdxFeedback::TicketClient — OAuth + ticket creation). Fallback: when TDX
  # isn't configured, or a submission errors, email the directory's admins so
  # feedback is never lost. Returns a Result (D7): payload[:via] is :tdx or
  # :email; :ticket_id present on the TDX path.
  class Submit
    def self.call(**kwargs) = new(**kwargs).call

    def initialize(message:, email:, category: nil, url: nil, user_agent: nil, additional_info: nil)
      @message = message
      @email = email
      @category = category
      @url = url
      @user_agent = user_agent
      @additional_info = additional_info
    end

    def call
      return email_fallback unless LsaTdxFeedback.configuration.valid?

      response = LsaTdxFeedback::TicketClient.new.create_feedback_ticket(ticket_data)
      Result.success(via: :tdx, ticket_id: response&.dig("ID"))
    rescue StandardError => e
      # TDX unreachable / OAuth failure / unexpected response — never fail the
      # user's submission over it; fall back to email and log the reason.
      Rails.logger.error("Feedback::Submit: TDX submission failed (#{e.class}: #{e.message}); falling back to email")
      email_fallback
    end

    private

    # Keys match LsaTdxFeedback::TicketClient#create_feedback_ticket's contract.
    def ticket_data
      { feedback: @message, email: @email, category: @category,
        url: @url, user_agent: @user_agent, additional_info: @additional_info }
    end

    def email_fallback
      recipients = admin_recipients
      if recipients.empty?
        Rails.logger.warn("Feedback::Submit: no admin recipients and no TDX config; feedback not delivered")
        return Result.failure("no_destination")
      end

      FeedbackMailer.submission(
        recipients: recipients, message: @message, email: @email, category: @category,
        url: @url, user_agent: @user_agent, additional_info: @additional_info
      ).deliver_later

      Result.success(via: :email)
    end

    # The directory's admins (owner/admin role slugs — the RoleResolver notion),
    # scoped through the workspace so this never loads memberships unscoped.
    def admin_recipients
      workspace = Current.workspace || TenancyConfig.shared_workspace
      return [] unless workspace

      workspace.memberships.kept
        .joins(:role).where(roles: { slug: RoleResolver::ADMIN_ROLE_SLUGS })
        .includes(:user).filter_map { |m| m.user&.email_address }.uniq
    end
  end
end
