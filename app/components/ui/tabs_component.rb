# frozen_string_literal: true

module UI
  # # Tabs
  #
  # A set of layered sections (WAI-ARIA APG tabs, AUTOMATIC activation) — one `role="tablist"`
  # of `role="tab"` buttons, each controlling a `role="tabpanel"`. The bar is roving (one tab
  # stop); ←/→ move focus and reveal that tab's panel, Home/End jump, disabled tabs are skipped.
  #
  # ## Use when
  # - Several peer sections share space and the user switches between them in place.
  #
  # ## Don't use when
  # - Navigating between URLs/pages — use links/`navbar`.
  #
  # ## Accessibility contract
  # - **Guarantees:** `role="tablist"` (named by `label:`); each `role="tab"` carries `id`,
  #   `aria-selected`, `aria-controls`, and roving tabindex; each `role="tabpanel"` carries
  #   `id`, `aria-labelledby`, `tabindex="0"` (focusable), and is `hidden` unless active. Full
  #   keyboard (←/→ activate + wrap, Home/End, skip-disabled, click).
  # - **You supply:** one or more `with_tab(title:)` slots, each with the panel content block.
  class TabsComponent < ApplicationComponent
    renders_many :tabs, "UI::TabsItemComponent"

    TABLIST = "inline-flex h-9 items-center justify-center rounded-lg bg-surface-sunken p-1 text-text-muted"
    # rubocop:disable Layout/LineLength
    TRIGGER = "inline-flex items-center justify-center whitespace-nowrap rounded-md px-3 py-1 text-sm font-medium transition-all focus-ring aria-disabled:pointer-events-none aria-disabled:opacity-50 data-[state=active]:bg-surface-raised data-[state=active]:text-text-heading data-[state=active]:shadow"
    # rubocop:enable Layout/LineLength
    PANEL = "mt-2 focus-ring"

    # label:    accessible name for the tablist (aria-label; required; i18n at the call site).
    # selected: index of the initially-active tab (default 0).
    # id:       base id (auto-generated; → tab/panel ids).
    def initialize(label:, selected: 0, id: nil, **html_attrs)
      @label = label
      @selected = selected.to_i
      @id = id || "tabs-#{SecureRandom.hex(4)}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:div, safe_join([ tablist, *panels ]),
        class: cn("w-full", @extra_class),
        data: { controller: "tabs", tabs_index_value: @selected }.merge(caller_data),
        **@html_attrs)
    end

    private

    def tablist
      content_tag(:div, safe_join(tabs.each_with_index.map { |tab, i| trigger(tab, i) }),
        role: "tablist",
        "aria-label": @label,
        "aria-orientation": "horizontal",
        class: TABLIST)
    end

    def trigger(tab, index)
      active = index == @selected
      attrs = {
        type: "button",
        role: "tab",
        id: tab_id(index),
        "aria-selected": active.to_s,
        "aria-controls": panel_id(index),
        tabindex: active ? "0" : "-1",
        data: {
          state: active ? "active" : "inactive",
          tabs_target: "tab",
          action: "click->tabs#select keydown->tabs#navigate"
        },
        class: TRIGGER
      }
      attrs[:"aria-disabled"] = "true" if tab.disabled?
      content_tag(:button, tab.title, **attrs)
    end

    def panels
      tabs.each_with_index.map do |tab, index|
        content_tag(:div, tab.to_s,
          role: "tabpanel",
          id: panel_id(index),
          "aria-labelledby": tab_id(index),
          tabindex: "0",
          hidden: index != @selected,
          data: { tabs_target: "panel" },
          class: PANEL)
      end
    end

    def tab_id(index)
      "#{@id}-tab-#{index}"
    end

    def panel_id(index)
      "#{@id}-panel-#{index}"
    end
  end
end
