require "rails_helper"

RSpec.describe "sessions/check_email", type: :view do
  before do
    assign(:email_address, "alice@example.com")
  end

  context "when running in development" do
    before { allow(Rails.env).to receive(:development?).and_return(true) }

    it "wraps the heading in a link to the letter_opener inbox" do
      render
      # Link surrounds the heading (WCAG 1.3.1 — clearer narration than heading-inside-link).
      expect(rendered).to have_css("a[href='/letter_opener'] h2", text: I18n.t("sessions.check_email.title"))
    end

    it "opens the letter_opener link in a new tab with noopener" do
      render
      expect(rendered).to have_css(
        %(a[href="/letter_opener"][target="_blank"][rel="noopener"])
      )
    end

    it "warns screen readers that the link opens a new window (WCAG 3.2.2)" do
      render
      expect(rendered).to have_css(
        "a[href='/letter_opener'] span.sr-only",
        text: I18n.t("sessions.check_email.opens_new_window")
      )
    end
  end

  context "when not running in development" do
    before { allow(Rails.env).to receive(:development?).and_return(false) }

    it "does not render any link to letter_opener" do
      render
      expect(rendered).not_to include("/letter_opener")
    end

    it "still renders the heading text" do
      render
      expect(rendered).to have_css("h2", text: I18n.t("sessions.check_email.title"))
    end

    it "does not render a new-window warning" do
      render
      expect(rendered).not_to include(I18n.t("sessions.check_email.opens_new_window"))
    end
  end
end
