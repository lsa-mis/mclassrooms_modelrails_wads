require "rails_helper"

RSpec.describe Feedback::Submit do
  let(:workspace) { create(:workspace, slug: "feedback-spec-workspace", personal: false) }
  before { Current.workspace = workspace }

  # An admin recipient for the email fallback path.
  let!(:admin) do
    user = create(:user, email_address: "admin@umich.edu")
    create(:membership, user: user, workspace: workspace, role: Role.system_default!("admin"))
    user
  end

  describe "email fallback (TDX not configured)" do
    it "emails the workspace admins and returns success via :email" do
      expect {
        result = described_class.call(message: "The panorama won't load", email: "u@umich.edu")
        expect(result.success?).to be true
        expect(result.payload[:via]).to eq(:email)
      }.to have_enqueued_mail(FeedbackMailer, :submission)
    end

    it "returns failure (and logs) when there are no admin recipients" do
      Membership.find_by(user: admin, workspace: workspace).destroy!

      result = described_class.call(message: "hi", email: "u@umich.edu")

      expect(result.success?).to be false
      expect(result.errors).to include("no_destination")
    end
  end

  describe "TDX path (configured)" do
    before { allow(LsaTdxFeedback.configuration).to receive(:valid?).and_return(true) }

    it "creates a TDX ticket and returns success via :tdx with the ticket id" do
      client = instance_double(LsaTdxFeedback::TicketClient)
      allow(LsaTdxFeedback::TicketClient).to receive(:new).and_return(client)
      allow(client).to receive(:create_feedback_ticket)
        .with(hash_including(feedback: "hi", email: "u@umich.edu", category: "bug"))
        .and_return({ "ID" => 4242 })

      result = described_class.call(message: "hi", email: "u@umich.edu", category: "bug", url: "/find-a-room")

      expect(result.success?).to be true
      expect(result.payload).to include(via: :tdx, ticket_id: 4242)
    end

    it "falls back to email (never fails the user) when the TDX submission raises" do
      allow(LsaTdxFeedback::TicketClient).to receive(:new).and_raise(LsaTdxFeedback::Error.new("boom"))

      expect {
        result = described_class.call(message: "hi", email: "u@umich.edu")
        expect(result.success?).to be true
        expect(result.payload[:via]).to eq(:email)
      }.to have_enqueued_mail(FeedbackMailer, :submission)
    end
  end
end
