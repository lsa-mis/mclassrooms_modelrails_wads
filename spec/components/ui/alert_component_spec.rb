# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::AlertComponent, type: :component do
  it "renders a neutral default as a polite status region" do
    render_inline(described_class.new(title: "Heads up"))

    expect(page).to have_css("div[role='status'][aria-live='polite']", text: "Heads up")
  end

  it "renders a destructive variant as an assertive alert region" do
    render_inline(described_class.new(variant: :destructive, title: "Couldn't save"))

    expect(page).to have_css("div[role='alert'][aria-live='assertive']", text: "Couldn't save")
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
end
