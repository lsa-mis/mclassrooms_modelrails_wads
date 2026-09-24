# frozen_string_literal: true

module UI
  # A horizontal application menubar (WAI-ARIA APG menubar) — a `role="menubar"` of top-level items, each opening a submenu.
  # Usage, options and the accessibility contract: docs/components/menubar.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class MenubarComponent < ApplicationComponent
    renders_many :menus, "UI::MenubarMenuComponent"

    BAR = "flex items-center gap-1 rounded-md border border-border bg-surface-raised p-1 shadow-xs"

    # label: the menubar's accessible name (aria-label), e.g. "Main". Required — a generic
    # default would silently pass axe's name-present check while leaving the role=menubar
    # container under-named (and ambiguous when a page has more than one).
    def initialize(label:, **html_attrs)
      @label = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:div, safe_join(menus),
        role: "menubar",
        "aria-label": @label,
        class: cn(BAR, @extra_class),
        data: {
          controller: "menubar",
          menubar_menu_outlet: "[data-menubar-item]",
          action: "keydown->menubar#navigate focusin->menubar#syncRoving"
        }.merge(caller_data),
        **@html_attrs)
    end
  end
end
