# frozen_string_literal: true

module UI
  # # Mega menu
  #
  # A disclosure button that reveals a full-width panel of grouped *navigation
  # links* (columns of titled link lists). Open/close is owned by the component's
  # own `mega-menu` Stimulus controller (a simple disclosure toggle).
  #
  # ## Menu-vs-nav semantics (deliberate)
  # This is a **disclosure + navigation region**, NOT the WAI-ARIA `menu` pattern,
  # so it does NOT reuse the shared `menu` controller (which `dropdown_menu`/`menubar`
  # consume). `role="menu"`/`menuitem` is for a list of *commands* with a roving-tabindex
  # arrow-key model; this panel holds ordinary `<a>` navigation links that must keep
  # native Tab/anchor behavior. Forcing `role=menu` here would impose a keyboard model
  # the links don't honour and remove them from the link/landmark trees. So: a real
  # `<button>` disclosure (`aria-expanded` + `aria-haspopup` + `aria-controls`) reveals a
  # named `<nav>` region of links.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup`, synced
  #   `aria-expanded`, and `aria-controls` pointing at the panel; the panel is a named
  #   `<nav>` landmark (`aria-label` ← the trigger label); the AAA `focus-ring` on the
  #   trigger and every link; outside-click dismissal; the chevron is decorative
  #   (`aria-hidden`).
  # - **You supply:** a `label:` (trigger text) and one or more `with_column` blocks.

  class MegaMenuComponent < ApplicationComponent
    TRIGGER_CLS = "focus-ring inline-flex h-11 items-center justify-center gap-1.5 rounded-md bg-surface-raised " \
                  "px-4 py-2 text-sm font-medium transition-[color,box-shadow] " \
                  "hover:bg-surface-sunken hover:text-text-heading " \
                  "data-[state=open]:bg-surface-sunken/50 data-[state=open]:text-text-heading"

    PANEL_CLS = "absolute left-0 top-full z-50 mt-1.5 w-full overflow-hidden rounded-md border " \
                "bg-surface-overlay text-text-body shadow-lg"

    INNER_CLS = "container mx-auto grid gap-6 p-6"

    COLUMN_HEADING = "mb-2 text-xs font-semibold uppercase tracking-wide text-text-muted"

    ITEM_CLS = "focus-ring group flex items-start gap-3 rounded-sm p-2 text-sm transition-colors " \
               "hover:bg-surface-sunken hover:text-text-heading"

    ITEM_TITLE = "font-medium leading-none"
    ITEM_DESC  = "mt-1 text-xs text-text-muted group-hover:text-text-heading/70"

    CHEVRON_PATH = "m6 9 6 6 6-6"

    renders_many :columns, "UI::MegaMenuComponent::ColumnComponent"

    # label:   trigger button text (also names the revealed <nav> landmark)
    # cols:    number of columns in the grid (default: auto based on column count)
    def initialize(label:, cols: nil, **html_attrs)
      @label = label
      @cols  = cols
      @id    = html_attrs.delete(:id) || "mega-menu-#{SecureRandom.hex(4)}"
      @panel_id = "#{@id}-panel"
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:div,
        id: @id,
        class: cn("relative", @extra_class),
        data: {
          controller: "mega-menu",
          action: "click@document->mega-menu#closeOnClickOutside"
        }.merge(caller_data),
        **@html_attrs) do
        concat trigger_btn
        concat panel
      end
    end

    private

    def trigger_btn
      content_tag(:button,
        type: "button",
        class: TRIGGER_CLS,
        "aria-haspopup": "true",
        "aria-expanded": "false",
        "aria-controls": @panel_id,
        data: { mega_menu_target: "trigger", state: "closed",
                action: "click->mega-menu#toggle" }) do
        concat @label
        concat chevron
      end
    end

    def panel
      col_count = @cols || [ columns.size, 1 ].max
      grid_cls  = "grid-cols-#{col_count}"

      content_tag(:nav,
        id: @panel_id,
        "aria-label": @label,
        hidden: true,
        class: PANEL_CLS,
        data: { mega_menu_target: "panel" }) do
        content_tag(:div, class: cn(INNER_CLS, grid_cls)) do
          safe_join(columns)
        end
      end
    end

    def chevron
      content_tag(:svg,
        content_tag(:path, nil, d: CHEVRON_PATH, "stroke-linecap": "round", "stroke-linejoin": "round"),
        xmlns: "http://www.w3.org/2000/svg",
        viewBox: "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        "stroke-width": "2",
        class: "size-3 transition-transform duration-200 data-[state=open]:rotate-180",
        "aria-hidden": "true",
        data: { mega_menu_target: "chevron" })
    end

    # A single column inside the mega menu panel.
    # heading: optional column title
    # items:   array of { title:, description:, href: } hashes
    class ColumnComponent < ApplicationComponent
      def initialize(heading: nil, items: [], **html_attrs)
        @heading    = heading
        @items      = items
        @html_attrs = html_attrs
      end

      def call
        content_tag(:div, **@html_attrs) do
          concat content_tag(:p, @heading, class: MegaMenuComponent::COLUMN_HEADING) if @heading
          concat(content_tag(:ul, class: "space-y-1") {
            safe_join(@items.map { |item| render_item(item) })
          })
        end
      end

      private

      def render_item(item)
        content_tag(:li) do
          content_tag(:a,
            href: item.fetch(:href, "#"),
            class: MegaMenuComponent::ITEM_CLS) do
            content_tag(:div) do
              concat content_tag(:p, item[:title], class: MegaMenuComponent::ITEM_TITLE)
              concat content_tag(:p, item[:description], class: MegaMenuComponent::ITEM_DESC) if item[:description]
            end
          end
        end
      end
    end
  end
end
