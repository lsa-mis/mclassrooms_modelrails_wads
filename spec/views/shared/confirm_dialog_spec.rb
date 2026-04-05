require "rails_helper"

RSpec.describe "shared/_confirm_dialog", type: :view do
  def render_dialog(**options)
    defaults = {
      title: "Delete Item",
      message: "This cannot be undone.",
      confirm_text: "Delete",
      confirm_url: "/items/1",
      confirm_method: :delete,
      variant: :danger
    }
    render(layout: "shared/confirm_dialog", locals: defaults.merge(options)) { "" }
  end

  describe "structure" do
    before { render_dialog }

    it "renders inside a modal" do
      expect(rendered).to have_css("dialog[role='dialog']")
    end

    it "shows the title" do
      expect(rendered).to have_css("h2", text: "Delete Item")
    end

    it "shows the message" do
      expect(rendered).to have_text("This cannot be undone.")
    end

    it "has a cancel button that closes the modal" do
      expect(rendered).to have_css("button[data-action='click->modal#close']", text: I18n.t("modals.cancel"))
    end

    it "has a confirm form posting to the correct URL" do
      expect(rendered).to have_css("form[action='/items/1']")
    end

    it "has a confirm button with the correct text" do
      expect(rendered).to have_css("form button[type='submit']", text: "Delete").or(
        have_css("form input[type='submit'][value='Delete']")
      )
    end
  end

  describe "danger variant" do
    before { render_dialog(variant: :danger) }

    it "shows the warning icon" do
      expect(rendered).to have_css(".text-danger-icon svg")
    end

    it "uses danger styling on confirm button" do
      expect(rendered).to have_css(".bg-danger")
    end
  end

  describe "default variant" do
    before { render_dialog(variant: :default) }

    it "shows the info icon" do
      expect(rendered).to have_css(".text-info-icon svg")
    end

    it "uses interactive styling on confirm button" do
      expect(rendered).to have_css(".bg-interactive")
    end
  end

  describe "custom options" do
    it "uses custom cancel text" do
      render_dialog(cancel_text: "Never mind")
      expect(rendered).to have_css("button", text: "Never mind")
    end

    it "uses custom id" do
      render_dialog(id: "delete-confirm")
      expect(rendered).to have_css("dialog#delete-confirm")
    end

    it "uses small modal size" do
      render_dialog
      expect(rendered).to have_css("[data-modal-target='panel'].max-w-sm")
    end
  end

  describe "accessibility" do
    before { render_dialog }

    it "cancel button has 44px touch target" do
      expect(rendered).to have_css("button.min-h-\\[44px\\]", text: I18n.t("modals.cancel"))
    end

    it "confirm button has 44px touch target" do
      expect(rendered).to have_css(".min-h-\\[44px\\]", text: "Delete")
    end

    it "modal has aria-labelledby" do
      expect(rendered).to have_css("dialog[aria-labelledby]")
    end
  end
end
