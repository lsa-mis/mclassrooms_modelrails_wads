module Settings
  class PasskeysController < ApplicationController
    layout "settings"
    before_action :require_reauthentication!, only: :destroy

    def index
      @passkeys = Current.user.webauthn_credentials.kept.order(:created_at)
    end

    def destroy
      Current.user.webauthn_credentials.kept.find(params[:id]).discard!
      redirect_to settings_passkeys_path, notice: t(".success")
    end
  end
end
