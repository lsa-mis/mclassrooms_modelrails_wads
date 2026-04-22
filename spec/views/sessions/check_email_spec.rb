require "rails_helper"

RSpec.describe "sessions/check_email", type: :view do
  before do
    assign(:email_address, "alice@example.com")
  end

  context "when running in development" do
    before { allow(Rails.env).to receive(:development?).and_return(true) }

    it "renders the heading as a link to the letter_opener inbox" do
      render
      expect(rendered).to have_link(
        I18n.t("sessions.check_email.title"),
        href: "/letter_opener"
      )
    end

    it "opens the letter_opener link in a new tab" do
      render
      expect(rendered).to have_css(
        %(a[href="/letter_opener"][target="_blank"][rel="noopener"])
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
  end
end
