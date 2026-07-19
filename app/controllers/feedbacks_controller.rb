class FeedbacksController < ApplicationController
  include DirectoryScoped

  def new
    authorize :feedback, :new?
    @feedback = FeedbackForm.new(email: Current.user.email_address)
  end

  def create
    authorize :feedback, :create?
    @feedback = FeedbackForm.new(feedback_params)
    @feedback.email = Current.user.email_address if @feedback.email.blank?

    return render :new, status: :unprocessable_entity unless @feedback.valid?

    result = Feedback::Submit.call(
      message: @feedback.message,
      email: @feedback.email,
      category: @feedback.category.presence,
      url: request.referer,
      user_agent: request.user_agent
    )

    if result.success?
      redirect_to new_feedback_path, notice: t("feedback.flash.submitted")
    else
      # Fallback destination unavailable — keep the entered values so the user
      # can retry (the form object + re-render preserve them).
      flash.now[:alert] = t("feedback.flash.retry")
      render :new, status: :unprocessable_entity
    end
  end

  private

  def feedback_params
    params.require(:feedback).permit(:message, :email, :category)
  end
end
