module Reauthenticatable
  extend ActiveSupport::Concern

  private

  # Gate a sensitive action behind a recent proof of a factor. As a
  # before_action it halts the request and sends the user to the interstitial;
  # after they prove a factor they land back on the page they came from and
  # retry the action, now within the reauth window.
  #
  # No-op when reauth is disabled (config/initializers/sessions.rb) so a fork
  # can turn the friction off without editing every gated controller.
  # `force:` opts a gate out of that switch: passkey enrollment stays gated
  # even when the fork disables reauth, because enrollment mints a durable
  # credential and revokes nothing (2026-08-12 reauth-defaults panel).
  def require_reauthentication!(force: false)
    return if !force && !Rails.configuration.x.session.reauth_enabled
    return if Current.session&.reauthenticated?

    store_reauthentication_return_to
    respond_to do |format|
      format.html { redirect_to new_settings_reauthentication_path }
      # XHR factor flows (passkey enrollment) get a signal to navigate rather
      # than an HTML redirect their fetch() can't follow.
      format.json do
        render json: { reauth_required: true, redirect_to: new_settings_reauthentication_path },
               status: :forbidden
      end
    end
  end

  # Return the user to the page they triggered the action from (a same-origin
  # referer), so after confirming they can retry it. Gated actions are all
  # mutating requests, so their own path isn't a useful landing.
  def store_reauthentication_return_to
    referer_path = url_from(request.referer)&.then { |uri| URI(uri).request_uri } rescue nil
    session[:return_to_after_reauthentication] = referer_path.presence || edit_settings_profile_path
  end

  def reauthentication_return_to
    session.delete(:return_to_after_reauthentication).presence || edit_settings_profile_path
  end
end
