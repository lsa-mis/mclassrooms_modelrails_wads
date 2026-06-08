# frozen_string_literal: true

module UI
  # One tab of a `tabs` group: a `title` (the tab button's visible label + accessible name)
  # plus the panel content (the block). Always used inside `UI::TabsComponent` via `with_tab`,
  # never standalone.
  class TabsItemComponent < ApplicationComponent
    attr_reader :title

    # title:    the tab button's label.
    # disabled: aria-disabled (skipped by roving/arrows), default false.
    def initialize(title:, disabled: false)
      @title = title
      @disabled = disabled
    end

    def disabled?
      @disabled
    end

    def call
      content
    end
  end
end
