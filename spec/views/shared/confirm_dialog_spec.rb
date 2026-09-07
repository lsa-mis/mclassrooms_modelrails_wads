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

    # A <dialog> opens with focus on its first focusable element (the header's
    # Close button) and the screen reader announces the dialog's name AND
    # description at that moment. Without aria-describedby the message is
    # never announced — the user hears "Delete Item, dialog. Close, button."
    it "renders as an alert dialog whose accessible description is the message" do
      expect(rendered).to have_css("dialog[role='alertdialog'][aria-describedby]")
      dialog = Capybara.string(rendered).find("dialog")
      expect(rendered).to have_css("##{dialog['aria-describedby']}", text: "This cannot be undone.")
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

    it "uses the .btn-danger component on the confirm button" do
      expect(rendered).to have_css("form button[type='submit'].btn-danger, form input[type='submit'].btn-danger")
    end
  end

  describe "default variant" do
    before { render_dialog(variant: :default) }

    it "shows the info icon" do
      expect(rendered).to have_css(".text-info-icon svg")
    end

    it "uses the .btn-primary component on the confirm button" do
      expect(rendered).to have_css("form button[type='submit'].btn-primary, form input[type='submit'].btn-primary")
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

    # An alertdialog is capped at max-w-md by UI::DialogComponent regardless of
    # size: — the role owns the width, so the partial passes no size.
    it "renders at the component's alertdialog width" do
      render_dialog
      expect(rendered).to have_css("[data-modal-target='panel'].max-w-md")
    end
  end

  describe "accessibility" do
    before { render_dialog }

    # The .btn-* component classes apply min-height via --form-input-height
    # (44px floor for WCAG 2.2 AAA touch targets). Asserting on the component
    # class — rather than the raw Tailwind arbitrary-value class — keeps the
    # test focused on the contract (a button gets the right component) rather
    # than the implementation detail (which utilities the component @applies).
    it "cancel button uses .btn-secondary (44px touch target via --form-input-height)" do
      expect(rendered).to have_css("button.btn-secondary", text: I18n.t("modals.cancel"))
    end

    it "confirm button uses a .btn-* component (44px touch target via --form-input-height)" do
      expect(rendered).to have_css("form .btn-danger, form .btn-primary", text: "Delete")
    end

    it "modal has aria-labelledby" do
      expect(rendered).to have_css("dialog[aria-labelledby]")
    end
  end
end
