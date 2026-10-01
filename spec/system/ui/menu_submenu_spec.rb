# frozen_string_literal: true

require "rails_helper"

# WAI-ARIA APG submenu keyboard model. The sub-trigger is an item of the parent menu, so
# it stays in the parent's arrow rotation; ArrowRight/Enter opens the submenu and moves
# focus into it, ArrowLeft/Escape closes it and returns focus to the sub-trigger.
RSpec.describe "Menu submenus", type: :system do
  let(:sub_trigger) { "[data-submenu-target=trigger]" }
  let(:sub_panel) { "[data-submenu-target=panel]" }

  before do
    visit "/rails/view_components/ui/dropdown_menu_component/submenus"
    find("[data-menu-target=trigger]").click
    expect(page).to have_css("[data-menu-target=menu]")
  end

  it "keeps the sub-trigger in the parent's arrow-key rotation" do
    cdp_press(:Down) # Edit -> Share

    expect(focused_text).to include("Share")
  end

  it "opens the submenu on ArrowRight and moves focus into it" do
    cdp_press(:Down)
    cdp_press(:Right)

    expect(page).to have_css(sub_panel)
    expect(focused_text).to eq("Email")
    expect(find(sub_trigger)["aria-expanded"]).to eq("true")
  end

  it "closes on ArrowLeft and returns focus to the sub-trigger" do
    cdp_press(:Down)
    cdp_press(:Right)
    expect(page).to have_css(sub_panel)

    cdp_press(:Left)

    expect(page).to have_no_css(sub_panel)
    expect(focused_text).to include("Share")
  end

  it "closes only the submenu on Escape, leaving the parent menu open" do
    cdp_press(:Down)
    cdp_press(:Right)

    cdp_press(:Escape)

    expect(page).to have_no_css(sub_panel)
    expect(page).to have_css("[data-menu-target=menu]")
  end

  it "navigates within the submenu" do
    cdp_press(:Down)
    cdp_press(:Right)

    cdp_press(:Down)

    expect(focused_text).to eq("Copy link")
  end

  # Closing the PARENT while a submenu is open used to leave the submenu popover-open with
  # aria-expanded="true" — an ARIA lie while the menu is shut — and reopening the parent
  # showed the submenu already expanded.
  describe "when the parent menu closes with a submenu open" do
    before do
      cdp_press(:Down)
      cdp_press(:Right)
      expect(page).to have_css(sub_panel)
      find("[data-menu-target=trigger]").click # toggle the parent shut
      expect(page).to have_no_css("[data-menu-target=menu]")
    end

    it "closes the submenu with it" do
      collapsed = page.evaluate_script(<<~JS)
        (() => { const el = document.querySelector("#{sub_panel}");
                 try { return !el.matches(":popover-open") } catch (e) { return true } })()
      JS

      expect(collapsed).to be(true)
    end

    it "stops claiming the submenu is expanded" do
      expect(find(sub_trigger, visible: :all)["aria-expanded"]).to eq("false")
    end

    it "reopens the parent with the submenu collapsed" do
      find("[data-menu-target=trigger]").click

      expect(page).to have_css("[data-menu-target=menu]")
      expect(page).to have_no_css(sub_panel)
    end
  end
end
