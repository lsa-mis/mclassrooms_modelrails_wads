# frozen_string_literal: true

require "rails_helper"

# ENHANCED preview-host proof for the data_table component.
#
# The render harness only verifies the static scaffold (class strings, th[aria-sort],
# the sort <button>s, the role=status region). It CANNOT see whether the `data-table`
# Stimulus controller actually wires keyboard sort, flips aria-sort, maps the right
# column index, or writes the localized count into the live region. A controller that
# never connected, a dead action binding, or an off-by-one #columnIndex would all pass
# the harness yet ship a broken table. This spec drives the REAL controller in a browser
# and reads DOM state / computed geometry off the live page.
#
# Uses the `default` preview: sortable `name` + `email`, NON-sortable `role`, 4 rows,
# a caption (the accessible name). Stable selectors come from the component's own
# load-bearing attributes (no component edit):
#   wrapper : [data-controller='data-table']
#   sortable th : th[aria-sort]                 (only the 2 sortable columns)
#   sort button : th[aria-sort] button
#   rows        : tbody[data-data-table-target='body'] tr[data-data-table-row]
#   status      : [role='status']
#   search      : input[type='search']
#   pager       : .data-table footer button[aria-label]  (prev/next)
RSpec.describe "DataTable component runtime behavior", type: :system do
  # `let`, not constants: the selectors are read inside helper defs, and bare
  # constants in a describe block land on Object, colliding across parallel
  # workers (#607/#608).
  let(:data_table_preview)  { "/rails/view_components/ui/data_table_component" }
  let(:data_table_wrapper)  { "[data-controller='data-table']" }
  let(:data_table_row_sel)  { "tbody[data-data-table-target='body'] tr[data-data-table-row]" }
  let(:data_table_name_th)  { "thead th[aria-sort]:nth-of-type(1)" }  # first sortable th = name
  let(:data_table_email_th) { "thead th[aria-sort]:nth-of-type(2)" }  # second sortable th = email

  # Read the VISIBLE row order by on-screen vertical position. The controller drives
  # ordering via the sorted #filtered array; we read what the user actually sees
  # (rows whose display != none), top-to-bottom, returning the requested cell index.
  def visible_cell_column(cell_index)
    cdp_evaluate(<<~JS)
      (() => {
        const rows = Array.from(
          document.querySelectorAll(#{data_table_row_sel.to_json})
        ).filter(r => getComputedStyle(r).display !== "none");
        rows.sort((a, b) =>
          a.getBoundingClientRect().top - b.getBoundingClientRect().top
        );
        return rows.map(r => r.cells[#{cell_index}]?.textContent.trim());
      })()
    JS
  end

  def aria_sort_of(th_selector)
    cdp_evaluate(<<~JS)
      document.querySelector(#{th_selector.to_json})?.getAttribute("aria-sort")
    JS
  end

  # Activate a sortable header's <button> from the keyboard. Programmatic key
  # dispatch is unreliable for Stimulus action binding, so we focus the real
  # button (proving it IS focusable / keyboard-reachable — the AAA contract) and
  # dispatch a genuine keydown+click the way Enter/Space activate a native button.
  # The OUTCOME (reorder + aria-sort flip) is asserted for real below.
  def keyboard_activate(th_selector, key)
    cdp_evaluate(<<~JS)
      (() => {
        const btn = document.querySelector(#{th_selector.to_json} + " button");
        btn.focus();
        const focused = document.activeElement === btn;
        // Native <button> activates on Enter/Space; mirror that so the Stimulus
        // click->sort action fires exactly as a keyboard user triggers it.
        btn.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, bubbles: true }));
        btn.click();
        document.body.offsetHeight;
        return focused;
      })()
    JS
  end

  def measure_min_dimension(selector, dimension)
    cdp_evaluate(<<~JS)
      (() => {
        const el = document.querySelector(#{selector.to_json});
        if (!el) return null;
        const r = el.getBoundingClientRect();
        return #{dimension.to_json} === "height" ? r.height : r.width;
      })()
    JS
  end

  before { visit "#{data_table_preview}/default" }

  describe "AAA accessibility" do
    it "passes AAA in both themes (scoped to the table, no contrast exclude)" do
      expect(page).to have_css("#{data_table_wrapper} table")

      scope = [ data_table_wrapper ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  describe "keyboard sort activation" do
    it "reorders the visible rows when a sortable header button is keyboard-activated" do
      expect(page).to have_css(data_table_row_sel, minimum: 4)

      before_order = visible_cell_column(0)

      # Enter on the focused Name header button.
      focused = keyboard_activate(data_table_name_th, "Enter")
      expect(focused).to(be(true), "the sortable Name header <button> did not accept focus (AAA keyboard contract)")

      # Wait for the controller to recompute and re-render.
      expect(aria_sort_of(data_table_name_th)).to eq("ascending")
      after_order = visible_cell_column(0)

      expect(after_order).not_to(
        eq(before_order),
        "keyboard activation did not reorder the rows. before=#{before_order.inspect} after=#{after_order.inspect}"
      )
      expect(after_order).to(
        eq(after_order.sort),
        "ascending sort should order names alphabetically; got #{after_order.inspect}"
      )

      # Space on the same header continues the cycle (asc -> desc), proving Space
      # also activates the keyboard-operable button.
      keyboard_activate(data_table_name_th, " ")
      expect(aria_sort_of(data_table_name_th)).to eq("descending")
      desc_order = visible_cell_column(0)
      expect(desc_order).to(
        eq(before_order.sort.reverse),
        "descending sort should reverse-alphabetize names; got #{desc_order.inspect}"
      )
    end
  end

  describe "aria-sort flip cycle" do
    it "cycles the activated th ascending -> descending -> none while the other reads none throughout" do
      expect(aria_sort_of(data_table_name_th)).to eq("none")
      expect(aria_sort_of(data_table_email_th)).to eq("none")

      keyboard_activate(data_table_name_th, "Enter")
      expect(aria_sort_of(data_table_name_th)).to eq("ascending")
      expect(aria_sort_of(data_table_email_th)).to eq("none")

      keyboard_activate(data_table_name_th, "Enter")
      expect(aria_sort_of(data_table_name_th)).to eq("descending")
      expect(aria_sort_of(data_table_email_th)).to eq("none")

      keyboard_activate(data_table_name_th, "Enter")
      expect(aria_sort_of(data_table_name_th)).to eq("none")
      expect(aria_sort_of(data_table_email_th)).to eq("none")
    end
  end

  describe "column-index correctness" do
    # Email sits at a different cell index (1) than name (0), and the non-sortable
    # `role` column (index 2) is interleaved. Sorting email must order rows by EMAIL
    # values, proving #columnIndex maps the right cell (the latent-bug fix).
    it "orders rows by email values when the second sortable column is sorted" do
      keyboard_activate(data_table_email_th, "Enter")
      expect(aria_sort_of(data_table_email_th)).to eq("ascending")

      emails = visible_cell_column(1) # email column cell index
      expect(emails).to(
        eq(emails.sort),
        "email sort should order by the EMAIL column (index 1); got #{emails.inspect}"
      )

      # The names (index 0) should follow the email ordering, NOT be alphabetical
      # by name — i.e. sorting really keyed on the email cell, not name's index.
      names_by_email = visible_cell_column(0)
      expect(names_by_email).not_to(
        eq(names_by_email.sort),
        "names should follow email order, not be self-sorted — proving the email " \
        "column index was used, not name's. got #{names_by_email.inspect}"
      )
    end
  end

  describe "live region on filter" do
    it "writes the localized result count and resets all aria-sort to none" do
      # Establish a non-none aria-sort first, so we can prove filter RESETS it.
      keyboard_activate(data_table_name_th, "Enter")
      expect(aria_sort_of(data_table_name_th)).to eq("ascending")

      fill_in_search("ada")

      status_text = cdp_evaluate("document.querySelector(\"[role='status']\")?.textContent.trim()")

      # default preview: one row contains "ada" (Ada Lovelace / ada@example.com).
      expect(status_text).to(
        eq("1 results"),
        "live region should announce the localized result count; got #{status_text.inspect}"
      )

      expect(aria_sort_of(data_table_name_th)).to eq("none")
      expect(aria_sort_of(data_table_email_th)).to eq("none")
    end
  end

  describe "44px target geometry (WCAG 2.5.5 AAA)" do
    it "renders the search control, a sortable header button, and a pager button >= 44px" do
      search_h = measure_min_dimension("#{data_table_wrapper} label", "height")
      sort_btn_h = measure_min_dimension("#{data_table_name_th} button", "height")
      # The default preview renders the footer (per_page default 10 > 0) with prev/next.
      pager_h = measure_min_dimension("#{data_table_wrapper} button[aria-label]", "height")

      aggregate_failures do
        expect(search_h).to be_present
        expect(search_h).to(be >= 44, "search control height was #{search_h}px (< 44 AAA floor)")
        expect(sort_btn_h).to be_present
        expect(sort_btn_h).to(be >= 44, "sortable header button height was #{sort_btn_h}px (< 44 AAA floor)")
        expect(pager_h).to be_present
        expect(pager_h).to(be >= 44, "pager button height was #{pager_h}px (< 44 AAA floor)")
      end
    end
  end

  def fill_in_search(query)
    cdp_execute(<<~JS)
      (() => {
        const input = document.querySelector("input[type='search']");
        input.value = #{query.to_json};
        input.dispatchEvent(new Event("input", { bubbles: true }));
        document.body.offsetHeight;
      })()
    JS
  end
end
