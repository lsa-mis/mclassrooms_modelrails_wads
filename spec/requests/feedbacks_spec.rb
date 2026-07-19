require "rails_helper"

RSpec.describe "Feedback", type: :request do
  let(:workspace) { create(:workspace, slug: "feedback-request-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # `create(:user)` auto-joins the shared workspace via User#onboard_workspace.
  let(:member) { create(:user) }

  describe "GET /feedback/new" do
    it "redirects an unauthenticated visitor to sign in" do
      get new_feedback_path

      expect(response).to have_http_status(:redirect)
    end

    it "renders the form for a signed-in user" do
      sign_in(member)

      get new_feedback_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("feedback.new.title"))
    end
  end

  describe "POST /feedback" do
    before { sign_in(member) }

    it "hands the submission to Feedback::Submit and redirects with a thank-you" do
      allow(Feedback::Submit).to receive(:call).and_return(Result.success(via: :email))

      post feedback_path, params: { feedback: { message: "The 360 view won't load", category: "bug" } }

      expect(Feedback::Submit).to have_received(:call)
        .with(hash_including(message: "The 360 view won't load", category: "bug"))
      expect(response).to redirect_to(new_feedback_path)
      expect(flash[:notice]).to eq(I18n.t("feedback.flash.submitted"))
    end

    it "re-renders (422) with the message preserved when submission has no destination" do
      allow(Feedback::Submit).to receive(:call).and_return(Result.failure("no_destination"))

      post feedback_path, params: { feedback: { message: "keep this text on retry" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("keep this text on retry")
      expect(flash[:alert]).to eq(I18n.t("feedback.flash.retry"))
    end

    it "re-renders (422) with the validation error for a blank message, without calling the service" do
      allow(Feedback::Submit).to receive(:call)

      post feedback_path, params: { feedback: { message: "   " } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("feedback.errors.blank_message"))
      expect(Feedback::Submit).not_to have_received(:call)
    end
  end
end
