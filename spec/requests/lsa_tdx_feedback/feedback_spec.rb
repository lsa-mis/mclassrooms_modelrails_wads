# frozen_string_literal: true

require "rails_helper"

# The adopted lsa_tdx_feedback modal POSTs here (the gem's JS -> our
# app/controllers override at LsaTdxFeedback::FeedbackController). These specs
# pin the controller's fork-specific posture; Feedback::Submit's own TDX/email-
# fallback branches are covered in spec/lib/feedback/submit_spec.rb.
RSpec.describe "Feedback submission (adopted modal)", type: :request do
  let(:payload) do
    { feedback: {
      category: "bug",
      feedback: "The room finder won't load results.",
      email: "visitor@example.com",
      url: "http://www.example.com/find-a-room",
      user_agent: "RSpec",
      additional_info: "Chrome on macOS"
    } }
  end

  def submit(body = payload)
    post "/lsa_tdx_feedback/feedback", params: body, as: :json
  end

  # Default the happy path through TDX so it doesn't depend on a shared
  # workspace — the suite runs in :personal posture, where the email fallback
  # has no admins to reach.
  before do
    allow(LsaTdxFeedback.configuration).to receive(:valid?).and_return(true)
    client = instance_double(LsaTdxFeedback::TicketClient, create_feedback_ticket: { "ID" => 4242 })
    allow(LsaTdxFeedback::TicketClient).to receive(:new).and_return(client)
  end

  it "accepts an UNAUTHENTICATED submission (no bounce to sign-in) in the modal's JSON shape" do
    submit

    expect(response).to have_http_status(:created) # not a 302 to /session/new
    body = response.parsed_body
    expect(body["success"]).to be(true)
    expect(body["message"]).to be_present           # the JS shows result.data.message
    expect(body["ticket_id"]).to eq(4242)
  end

  it "delegates every modal field (incl. additional_info) to Feedback::Submit" do
    expect(Feedback::Submit).to receive(:call).with(
      hash_including(
        message: "The room finder won't load results.",
        email: "visitor@example.com",
        category: "bug",
        url: "http://www.example.com/find-a-room",
        user_agent: "RSpec",
        additional_info: "Chrome on macOS"
      )
    ).and_return(Result.success(via: :tdx, ticket_id: 4242))

    submit
    expect(response).to have_http_status(:created)
  end

  it "rejects a blank message with 422 in the modal's JSON shape (server-side guard)" do
    submit(feedback: payload[:feedback].merge(feedback: "   "))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["success"]).to be(false)
    expect(response.parsed_body["message"]).to be_present
  end

  it "surfaces a delivery failure as 422 (never a 500) so the modal can prompt a retry" do
    allow(Feedback::Submit).to receive(:call).and_return(Result.failure("no_destination"))

    submit

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["success"]).to be(false)
  end

  context "signed-in submitter who clears the email field" do
    it "falls back to the account email" do
      user = create(:user, email_address: "member@umich.edu")
      sign_in(user)

      expect(Feedback::Submit).to receive(:call)
        .with(hash_including(email: "member@umich.edu"))
        .and_return(Result.success(via: :tdx, ticket_id: 1))

      submit(feedback: payload[:feedback].merge(email: ""))
      expect(response).to have_http_status(:created)
    end
  end

  it "rate-limits abusive bursts with a 429 in the modal's JSON shape" do
    # Test-env cache is :null_store, so real counting is inert (as for every
    # other rate_limit in the app). Stub the store the limiter captured at
    # class-load to force it past threshold, exercising our 429 handler + JSON.
    allow(LsaTdxFeedback::FeedbackController.cache_store)
      .to receive(:increment).and_return(999)

    submit

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body["success"]).to be(false)
    expect(response.parsed_body["message"]).to be_present
  end
end
