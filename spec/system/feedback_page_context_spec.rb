# frozen_string_literal: true

require "rails_helper"

# The page a user was on when they opened the modal travels with the submission
# (hidden url field -> Feedback::Submit -> "Page URL:" in the TDX ticket, or
# "Page:" in the admin fallback email). The field is baked in at render time, so
# this guards that Turbo Drive navigation re-renders it rather than leaving a
# stale page behind.
RSpec.describe "Feedback modal — page context", type: :system do
  def captured_url
    find('#lsa-tdx-feedback-form input[name="url"]', visible: :all).value
  end

  it "captures the current page, and refreshes it across Turbo navigation" do
    visit about_path
    expect(captured_url).to end_with("/about")

    click_link I18n.t("footer.contact")
    expect(page).to have_current_path(contact_path)

    expect(captured_url).to end_with("/contact")
  end
end
