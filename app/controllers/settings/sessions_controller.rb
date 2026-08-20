module Settings
  class SessionsController < ApplicationController
    def index
      @sessions = Current.user.sessions.active.order(last_active_at: :desc)
    end

    def destroy
      session = Current.user.sessions.find(params[:id])

      if session.id == Current.session.id
        terminate_session
        redirect_to new_session_path, status: :see_other, notice: t(".signed_out_current")
      else
        session.destroy
        redirect_to settings_sessions_path, notice: t(".signed_out", device: session.device_label)
      end
    end
  end
end
