# frozen_string_literal: true

require "rails_helper"

# The adopted feedback modal + its trigger render site-wide from the layout
# tail. These pin the FEEDBACK_FLOATING_TRIGGER toggle: the modal is always
# present (our footer/CTA controls open it), and the gem's floating button is
# opt-out via config.
RSpec.describe "Feedback widget (site-wide)", type: :request do
  it "renders the modal on a public page" do
    get about_path
    expect(response.body).to include('id="lsa-tdx-feedback-modal"')
  end

  it "renders the floating trigger by default" do
    get about_path
    expect(response.body).to include('id="lsa-tdx-feedback-trigger"')
  end

  it "omits the floating trigger when FEEDBACK_FLOATING_TRIGGER is off (modal still present)" do
    original = Rails.configuration.x.feedback_floating_trigger
    Rails.configuration.x.feedback_floating_trigger = false

    get about_path
    expect(response.body).not_to include('id="lsa-tdx-feedback-trigger"')
    expect(response.body).to include('id="lsa-tdx-feedback-modal"')
  ensure
    Rails.configuration.x.feedback_floating_trigger = original
  end
end
