# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::RadioGroupComponent, type: :component do
  plan_items = [
    { value: "free", label: "Free" },
    { value: "pro", label: "Pro" },
    { value: "team plan", label: "Team plan" }
  ].freeze

  it "renders a named radiogroup with an accessible name" do
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: plan_items))

    # A role=radiogroup MUST carry an accessible name (empty group name is an a11y failure).
    expect(page).to have_css("div[role='radiogroup'][aria-label='Billing plan']")
  end

  it "renders each item as a radio input with a matching label" do
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: plan_items))

    plan_items.each do |item|
      id = "plan_#{item[:value].gsub(/\W/, "_")}"

      expect(page).to have_css("input[type='radio'][name='plan'][value='#{item[:value]}'][id='#{id}']")
      expect(page).to have_css("label[for='#{id}']", text: item[:label])
    end
  end

  it "marks only the checked item" do
    items = [
      { value: "free", label: "Free" },
      { value: "pro", label: "Pro", checked: true }
    ]
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: items))

    expect(page).to have_css("input[type='radio'][id='plan_pro'][checked]")
    expect(page).not_to have_css("input[type='radio'][id='plan_free'][checked]")
  end

  it "honors a disabled item" do
    items = [
      { value: "free", label: "Free" },
      { value: "enterprise", label: "Enterprise", disabled: true }
    ]
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: items))

    expect(page).to have_css("input[type='radio'][id='plan_enterprise'][disabled]")
    expect(page).not_to have_css("input[type='radio'][id='plan_free'][disabled]")
  end

  it "sets aria-invalid on the group when invalid" do
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: plan_items, invalid: true))

    expect(page).to have_css("div[role='radiogroup'][aria-invalid='true']")
  end

  it "does not set aria-invalid when invalid is absent" do
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: plan_items))

    expect(page).not_to have_css("div[role='radiogroup'][aria-invalid]")
  end

  it "links the group to a hint or error via describedby" do
    render_inline(
      described_class.new(
        name: "plan", label: "Billing plan", items: plan_items, describedby: "plan-error"
      )
    )

    expect(page).to have_css("div[role='radiogroup'][aria-describedby='plan-error']")
  end

  it "does not set aria-describedby when describedby is absent" do
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: plan_items))

    expect(page).not_to have_css("div[role='radiogroup'][aria-describedby]")
  end

  it "does not let caller html attrs clobber the group's a11y contract" do
    render_inline(
      described_class.new(
        name: "plan", label: "Billing plan", items: plan_items, invalid: true,
        role: "group", "aria-label": "Caller override", "aria-invalid": "false"
      )
    )

    # Component wins: its role/aria-label/aria-invalid survive caller-supplied conflicts.
    expect(page).to have_css("div[role='radiogroup'][aria-label='Billing plan'][aria-invalid='true']")
    expect(page).not_to have_css("div[role='group']")
    expect(page).not_to have_css("div[aria-label='Caller override']")
  end

  # AAA semantic tokens (the design-token guarantee), not raw Tailwind:
  it "renders inputs with semantic AAA tokens" do
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: plan_items))

    expect(page).to have_css("input.border-interactive")
    expect(page).to have_css("input.accent-interactive")
  end

  # Standard library focus indicator (the focus-ring outline utility), matching the other form controls.
  it "renders inputs with the standard focus-ring outline" do
    render_inline(described_class.new(name: "plan", label: "Billing plan", items: plan_items))

    expect(page).to have_css("input.focus-ring")
  end
end
