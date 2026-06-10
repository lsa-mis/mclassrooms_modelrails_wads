# frozen_string_literal: true

module UI
  # # SearchInput
  #
  # A standalone `<input type="search">` with a decorative magnifier icon, AAA
  # field styling, and an always-present accessible name.
  #
  # ## Use when
  # - A one-off search / filter box outside a `form_with`: a list filter, a header
  #   site-search field, a command-bar trigger.
  #
  # ## Don't use when
  # - You are inside a `form_with` block — call `f.search_field :attr` instead.
  # - You need the full sortable/filterable table toolbar — use `data_table`.
  #
  # ## Accessibility contract
  # - **Guarantees:** an `aria-label` accessible name on every instance (a placeholder
  #   is only a hint), an `aria-hidden` magnifier icon, the AAA 44px target floor
  #   (`h-11`), and AAA border/focus-ring tokens.
  # - **You supply:** on error, `invalid: true` + `describedby:`; a custom `label:`
  #   when "Search" is the wrong accessible name.
  # @logical_path Forms & Inputs
  class SearchInputComponentPreview < ViewComponent::Preview
    include UIHelper

    # Baseline: a labelled search box. The accessible name defaults to "Search".
    def default
    end

    # A domain-specific accessible name via `label:` (overrides the "Search" default).
    def labelled
    end

    # Error state — `aria-invalid` wired to a described-by hint message.
    def invalid
    end

    # ## Don't — strip the accessible name
    #
    # A placeholder is only a hint, not an accessible name. Blanking `label:` (or
    # writing a bare `<input type="search">`) leaves the control unnamed — screen
    # readers announce no purpose. Always keep an accessible name.
    # @label Don't · no accessible name
    def dont_no_accessible_name
    end
  end
end
