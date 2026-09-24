# frozen_string_literal: true

module UI
  # One tab of a `tabs` group: a `title` (the tab button's visible label + accessible name) plus the panel content (the block).
  # Usage, options and the accessibility contract: docs/components/tabs.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
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
