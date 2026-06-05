# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::AlertComponent, type: :component do
  it "renders a neutral default as a polite status region" do
    render_inline(described_class.new(title: "Heads up"))

    expect(page).to have_css("div[role='status'][aria-live='polite']", text: "Heads up")
  end

  it "renders a danger variant as an assertive alert on the danger surface" do
    render_inline(described_class.new(variant: :danger, title: "Couldn't save"))

    expect(page).to have_css("div[role='alert'][aria-live='assertive'].bg-danger-surface", text: "Couldn't save")
  end

  # `destructive` is a non-breaking alias for the canonical `danger`.
  it "renders the destructive alias identically to danger" do
    render_inline(described_class.new(variant: :destructive, title: "Couldn't save"))

    expect(page).to have_css("div[role='alert'][aria-live='assertive'].bg-danger-surface", text: "Couldn't save")
  end

  it "renders a warning variant as a polite status on the warning surface" do
    render_inline(described_class.new(variant: :warning, title: "Heads up"))

    expect(page).to have_css("div[role='status'][aria-live='polite'].bg-warning-surface", text: "Heads up")
  end

  it "renders title and description slots" do
    render_inline(described_class.new(variant: :destructive)) do |alert|
      alert.with_alert_title { "2 errors" }
      alert.with_alert_description { "Title can't be blank" }
    end

    expect(page).to have_css("h5", text: "2 errors")
    expect(page).to have_css("div[data-slot='alert-description']", text: "Title can't be blank")
  end

  it "raises on an unknown variant in test" do
    expect { render_inline(described_class.new(variant: :bogus)) }
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
