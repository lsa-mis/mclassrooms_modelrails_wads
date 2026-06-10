# frozen_string_literal: true

module UI
  # # Breadcrumb
  #
  # A breadcrumb trail. The last item is the current page (aria-current=page, not a link).
  # @logical_path Navigation
  class BreadcrumbComponentPreview < ViewComponent::Preview
    include UIHelper

    # Home / Library / Data (Data = current page).
    def basic
    end
  end
end
