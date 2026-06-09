# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::AlertComponent, type: :component do
  it "renders a neutral default as a polite status region" do
    render_inline(described_class.new(title: "Heads up"))

    expect(page).to have_css("div[role='status'][aria-live='polite']", text: "Heads up")
  end

  # The deprecated `variant:` axis is still honored for legacy call sites.
  describe "deprecated variant: alias" do
    it "renders variant: :default on the raised surface as a polite status" do
      render_inline(described_class.new(variant: :default, title: "Heads up"))

      expect(page).to have_css("div[role='status'][aria-live='polite'].bg-surface-raised", text: "Heads up")
    end

    it "renders variant: :danger as an assertive alert on the danger surface" do
      render_inline(described_class.new(variant: :danger, title: "Couldn't save"))

      expect(page).to have_css("div[role='alert'][aria-live='assertive'].bg-danger-surface", text: "Couldn't save")
    end

    # `destructive` maps onto the canonical `danger`.
    it "renders variant: :destructive identically to danger" do
      render_inline(described_class.new(variant: :destructive, title: "Couldn't save"))

      expect(page).to have_css("div[role='alert'][aria-live='assertive'].bg-danger-surface", text: "Couldn't save")
    end
  end

  # The canonical single tone: axis.
  describe "tone:" do
    it "renders tone: :neutral identically to the legacy variant: :default" do
      render_inline(described_class.new(tone: :neutral, title: "Heads up"))

      expect(page).to have_css("div[role='status'][aria-live='polite'].bg-surface-raised", text: "Heads up")
    end

    it "renders tone: :warning as a polite status on the warning surface" do
      render_inline(described_class.new(tone: :warning, title: "Heads up"))

      expect(page).to have_css("div[role='status'][aria-live='polite'].bg-warning-surface", text: "Heads up")
    end
  end

  it "renders title and description slots" do
    render_inline(described_class.new(tone: :danger)) do |alert|
      alert.with_alert_title { "2 errors" }
      alert.with_alert_description { "Title can't be blank" }
    end

    expect(page).to have_css("h5", text: "2 errors")
    expect(page).to have_css("div[data-slot='alert-description']", text: "Title can't be blank")
  end

  it "raises on an unknown tone in test" do
    expect { render_inline(described_class.new(tone: :bogus)) }
      .to raise_error(ArgumentError)
  end

  it "passes through html attributes onto the root" do
    render_inline(described_class.new(title: "Heads up", id: "save-alert", data: { testid: "alert" }))

    expect(page).to have_css("div#save-alert[role='status'][data-testid='alert']")
  end

  it "merges a caller-supplied class onto the root without clobbering the variant tokens" do
    render_inline(described_class.new(title: "Heads up", class: "mt-4"))

    expect(page).to have_css("div.mt-4.bg-surface-raised")
  end
end
