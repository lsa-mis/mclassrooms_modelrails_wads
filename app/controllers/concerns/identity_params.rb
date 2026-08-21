# frozen_string_literal: true

# Identity-picker wire protocol: the picker JS posts these top-level
# avatar-named params for BOTH User and Workspace (frozen — the client posts
# the same names regardless of model). Controllers layer model-specific
# extras (e.g. WorkspacesController's logo-named non-JS fallbacks and `name`)
# on top via merge; the shared protocol lives only here.
module IdentityParams
  private

  def identity_wire_params
    {
      image: params[:avatar],
      image_original: params[:avatar_original],
      crop_coordinates: params[:crop_coordinates],
      source: params[:avatar_source],
      color: params[:primary_color]
    }
  end
end
