# frozen_string_literal: true

require "rails_helper"

# Checkable menu items follow the WAI-ARIA APG menu pattern: `menuitemcheckbox` /
# `menuitemradio` carrying `aria-checked`, rendered from server state so the menu is
# correct before any JS runs. `menu_controller` then toggles that state in place.
RSpec.describe UI::DropdownMenuComponent, type: :component do
  # The panel renders `hidden` (closed), so every query is visible: :all.
  def menu(&block)
    render_inline(described_class.new) do |c|
      c.with_trigger { "Actions" }
      block.call(c)
    end
  end

  describe "checkbox items" do
    it "renders the APG role and reflects server-side state" do
      menu do |c|
        c.with_item(checkbox: true, checked: true) { "Show grid" }
        c.with_item(checkbox: true) { "Show rulers" }
      end

      checked, unchecked = page.all("[role=menuitemcheckbox]", visible: :all)
      expect(checked["aria-checked"]).to eq("true")
      expect(unchecked["aria-checked"]).to eq("false")
    end

    it "keeps a plain item free of checkable semantics" do
      menu { |c| c.with_item { "Edit" } }

      expect(page).to have_css("[role=menuitem]", visible: :all)
      expect(page.first("[role=menuitem]", visible: :all)["aria-checked"]).to be_nil
    end
  end

  describe "radio items" do
    it "renders the APG role and marks only the selected option" do
      menu do |c|
        c.with_item(radio: "density", value: "cosy") { "Cosy" }
        c.with_item(radio: "density", value: "compact", checked: true) { "Compact" }
      end

      items = page.all("[role=menuitemradio]", visible: :all)
      expect(items.map { |i| i["aria-checked"] }).to eq(%w[false true])
      expect(items.map { |i| i["data-menu-radio-group"] }).to all(eq("density"))
    end
  end

  describe "destructive items" do
    # `tone:` is the same signal vocabulary as button/badge. Asserted through the
    # data attribute (the role contract) rather than the class string, so restyling
    # does not churn the spec.
    it "marks the item with the danger tone" do
      menu { |c| c.with_item(tone: :danger) { "Delete" } }

      expect(page).to have_css("[role=menuitem][data-tone=danger]", visible: :all)
    end

    it "rejects a tone outside the signal vocabulary" do
      expect { menu { |c| c.with_item(tone: :purple) { "Nope" } } }
        .to raise_error(ArgumentError, /tone/)
    end
  end
end
