# frozen_string_literal: true

require "rails_helper"

# STRUCTURE-only render specs. The data-table Stimulus controller's behavior
# (aria-sort flipping on click, the live region announcing result counts on
# filter, page-label interpolation) is verified by a pass-B browser spec — the
# render harness CANNOT exercise JS, so we assert the static scaffolding the
# controller relies on, never the runtime behavior itself.
RSpec.describe UI::DataTableComponent, type: :component do
  columns = [
    { key: :name, label: "Name", sortable: true },
    { key: :email, label: "Email", sortable: true },
    { key: :role, label: "Role" } # non-sortable
  ].freeze

  rows = [
    { name: "Ada", email: "ada@example.com", role: "Admin" },
    { name: "Babbage", email: "chuck@example.com", role: "Member" }
  ].freeze

  def render_default(**overrides)
    render_inline(described_class.new(columns: DATA_TABLE_COLUMNS, rows: DATA_TABLE_ROWS, **overrides))
  end

  DATA_TABLE_COLUMNS = columns
  DATA_TABLE_ROWS = rows

  # --- Keyboard-operable sort header + aria-sort -----------------------------

  # A sortable column renders th[aria-sort='none'] containing a focusable
  # <button> that carries the sort action + key param. The button (not the th)
  # is keyboard-operable for free.
  it "renders a sortable header as a button inside an aria-sort th" do
    render_default

    expect(page).to have_css("th[aria-sort='none'] button[type='button'][data-action~='click->data-table#sort']")
    expect(page).to have_css("th[aria-sort='none'] button[data-data-table-key-param='name']")
    expect(page).to have_css("th[aria-sort='none'] button[data-data-table-key-param='email']")
  end

  # The click handler must live on the BUTTON, not the (non-focusable) <th>.
  it "does not put the sort action on the th itself" do
    render_default

    expect(page).not_to have_css("th[data-action~='click->data-table#sort']")
  end

  # Non-sortable columns stay a plain <th> with no aria-sort and no sort button.
  it "leaves non-sortable headers without aria-sort and without a button" do
    render_default

    role_th = page.find("th", text: "Role")

    expect(role_th[:"aria-sort"]).to be_nil
    expect(page).not_to have_css("th button[data-data-table-key-param='role']")
  end

  # --- Live region for result count -----------------------------------------

  # An always-present visually-hidden polite status region the controller
  # writes the localized result count into on filter/sort/page.
  it "renders a polite status live region" do
    render_default

    expect(page).to have_css("div[role='status'][aria-live='polite'].sr-only[data-data-table-target='status']")
  end

  # --- 44px AAA targets (WCAG 2.5.5) -----------------------------------------

  it "renders 44px pager buttons" do
    render_default(per_page: 1)

    expect(page).to have_css("button.h-11.w-11", minimum: 2) # prev + next
  end

  it "renders a 44px-tall search control" do
    render_default

    expect(page).to have_css("label.h-11") # the search wrapper row
  end

  it "renders a sortable header button at least 44px tall" do
    render_default

    # The header button fills the (>=44px) cell height.
    expect(page).to have_css("th button.min-h-11")
  end

  # --- AAA semantic tokens, not raw Tailwind ---------------------------------

  it "renders with AAA semantic tokens" do
    render_default

    expect(page).to have_css("div.border-border") # wrapper
    expect(page).to have_css("th.text-text-muted") # header cell
  end

  # --- i18n: server-rendered defaults ----------------------------------------

  it "renders the search input with a default placeholder and accessible name" do
    render_default

    expect(page).to have_css("input[type='search'][placeholder='Search…']")
    expect(page).to have_css("input[type='search'][aria-label='Search']")
  end

  it "renders default pager aria-labels" do
    render_default(per_page: 1)

    expect(page).to have_css("button[aria-label='Previous page']")
    expect(page).to have_css("button[aria-label='Next page']")
  end

  # --- i18n: JS templates exposed as data attributes on the root -------------

  # The controller interpolates these %{...} templates client-side; the render
  # harness only asserts they are present with their default English text.
  it "exposes the JS interpolation templates on the root" do
    render_default

    root = page.find("div[data-controller~='data-table']")

    expect(root["data-data-table-results-template"]).to eq("%{count} results")
    expect(root["data-data-table-page-template"]).to eq("Page %{page} of %{pages} (%{rows} rows)")
  end

  # --- Rows / cells / caption ------------------------------------------------

  it "renders rows and cells" do
    render_default

    expect(page).to have_css("tbody tr[data-data-table-row]", count: 2)
    expect(page).to have_css("td", text: "ada@example.com")
    expect(page).to have_css("td", text: "Admin")
  end

  it "renders a caption when given" do
    render_default(caption: "Active users")

    expect(page).to have_css("caption", text: "Active users")
  end

  it "renders no caption by default" do
    render_default

    expect(page).not_to have_css("caption")
  end
end
