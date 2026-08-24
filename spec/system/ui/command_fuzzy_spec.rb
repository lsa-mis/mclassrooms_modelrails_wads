# frozen_string_literal: true

require "rails_helper"

# The filter was substring-only and preserved source order, so a palette could not find
# "New document" from "nd" and could not put the best match first. Ranking is most of what
# makes a command palette feel like one.
RSpec.describe "Command palette fuzzy ranking", type: :system do
  # The palette is a modal dialog: the input does not exist until the trigger opens it.
  def open_palette
    visit "/rails/view_components/ui/command_component/fuzzy_ranking"
    find("button", text: "⌘K").click
    expect(page).to have_css("[data-command-target=input]")
  end

  def visible_items
    page.all("[data-command-value]:not([hidden])").map(&:text)
  end

  def search(query)
    find("[data-command-target=input]").set(query)
  end

  # `set("")` does not dispatch an `input` event, so the filter never re-runs and the
  # assertion would read the previous query's state. Backspaces are what a user actually
  # does, and they fire the event.
  def clear_search
    field = find("[data-command-target=input]")
    field.send_keys(*Array.new(field.value.length) { :backspace })
  end

  before { open_palette }

  it "matches a subsequence that is not a substring" do
    search("nd")

    expect(visible_items).to eq([ "New document" ])
  end

  # The control: proves the case above needs fuzzy matching rather than passing by luck.
  it "confirms that query is not a substring of the item" do
    expect("New document".downcase).not_to include("nd")
  end

  it "ranks the better match first" do
    search("gp")

    expect(visible_items.first).to eq("Group Policy")
  end

  it "finds an item by a keyword it does not display" do
    search("configuration")

    expect(visible_items).to eq([ "Settings" ])
  end

  it "hides items that do not match at all" do
    search("zzzz")

    expect(visible_items).to be_empty
    expect(page).to have_css("[data-command-target=empty]:not([hidden])")
  end

  it "restores the authored order when the query is cleared" do
    search("gp")
    clear_search

    expect(visible_items).to eq([ "Groups", "Group Policy", "Settings", "New document" ])
  end
end
