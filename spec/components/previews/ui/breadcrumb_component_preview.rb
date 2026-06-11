# frozen_string_literal: true

module UI
  # # Breadcrumb
  #
  # A breadcrumb trail. The last item is the current page (aria-current=page, not a link).
  #
  # ## Use when
  # - Showing where the current page sits in a hierarchy, with links back up the trail.
  #
  # ## Don't use when
  # - You're switching between in-page panels — use `tabs`.
  # - It's the site's primary navigation — use `navbar`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark wrapping an ordered list; the last item
  #   is the current page — `aria-current="page"`, rendered as text, not a link.
  # - **You supply:** the trail items (label + href); the final item's label.
  # @logical_path Navigation
  class BreadcrumbComponentPreview < ViewComponent::Preview
    include UIHelper

    # Home / Library / Data (Data = current page).
    def basic
    end
  end
end
