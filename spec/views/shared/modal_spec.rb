require "rails_helper"

RSpec.describe "shared/_modal", type: :view do
  def render_modal(**options)
    content = options.delete(:content) || "test content"
    render(layout: "shared/modal", locals: options) { content }
  end

  describe "size classes" do
    it "defaults to max-w-lg for :md" do
      render_modal(title: "Test")
      expect(rendered).to have_css("[data-modal-target='panel'].max-w-lg")
    end

    it "uses max-w-sm for :sm" do
      render_modal(title: "Test", size: :sm)
      expect(rendered).to have_css("[data-modal-target='panel'].max-w-sm")
    end

    it "uses max-w-2xl for :lg" do
      render_modal(title: "Test", size: :lg)
      expect(rendered).to have_css("[data-modal-target='panel'].max-w-2xl")
    end

    it "uses max-w-4xl for :full" do
      render_modal(title: "Test", size: :full)
      expect(rendered).to have_css("[data-modal-target='panel'].max-w-4xl")
    end
  end

  describe "ID generation" do
    it "uses provided id" do
      render_modal(title: "Test", id: "my-modal")
      expect(rendered).to have_css("dialog#my-modal")
      expect(rendered).to have_css("h2#my-modal-title")
      expect(rendered).to have_css("dialog[aria-labelledby='my-modal-title']")
    end

    it "generates a unique id when none provided" do
      render_modal(title: "Test")
      expect(rendered).to have_css("dialog[id^='modal-']")
    end
  end

  describe "title" do
    it "renders the title in an h2" do
      render_modal(title: "Edit Profile")
      expect(rendered).to have_css("h2", text: "Edit Profile")
    end
  end

  describe "description" do
    it "renders description when provided" do
      render_modal(title: "Test", description: "A helpful description")
      expect(rendered).to have_css("p[id$='-description']", text: "A helpful description")
    end

    it "adds aria-describedby when description is provided" do
      render_modal(title: "Test", id: "desc-modal", description: "Help text")
      expect(rendered).to have_css("dialog[aria-describedby='desc-modal-description']")
      expect(rendered).to have_css("p#desc-modal-description", text: "Help text")
    end

    it "does not add aria-describedby when no description" do
      render_modal(title: "Test")
      expect(rendered).not_to have_css("dialog[aria-describedby]")
    end
  end

  describe "content" do
    it "yields the block content" do
      render_modal(title: "Test", content: "<p class='test-content'>Hello</p>".html_safe)
      expect(rendered).to have_css("p.test-content", text: "Hello")
    end
  end

  describe "structure" do
    before { render_modal(title: "Test") }

    it "has overflow handling on the body" do
      expect(rendered).to have_css("div.overflow-y-auto")
    end

    it "uses surface-overlay background" do
      expect(rendered).to have_css("[data-modal-target='panel'].bg-surface-overlay")
    end

    it "has a 44px close button" do
      expect(rendered).to have_css("button.min-h-\\[44px\\].min-w-\\[44px\\]")
    end

    it "close button has aria-label" do
      expect(rendered).to have_css("button[aria-label='#{I18n.t("modals.close")}']")
    end
  end
end
