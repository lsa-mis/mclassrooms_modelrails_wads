# Declares which settings sidebar a controller renders.
#
# Each settings-rendering controller calls the class macro once:
#   settings_context :identity    # => shared/_identity_settings_sidebar_items
#   settings_context :workspace   # => shared/_workspace_settings_sidebar_items
#
# The layout reads settings_sidebar_partial (a helper_method exposed to views)
# to render the matching partial — no personal?/org? branching anywhere in the
# view layer. The context is set by the controller, not derived from workspace
# state, so WorkspacesController#edit correctly renders the workspace sidebar
# even when the active workspace is personal?.
module SettingsContext
  extend ActiveSupport::Concern

  included do
    helper_method :settings_sidebar_partial, :settings_context_value
  end

  class_methods do
    def settings_context(kind)
      before_action { @settings_context = kind }
    end
  end

  def settings_sidebar_partial
    case @settings_context
    when :workspace
      "shared/workspace_settings_sidebar_items"
    else
      "shared/identity_settings_sidebar_items"
    end
  end

  def settings_context_value
    @settings_context&.to_s || "identity"
  end
end
