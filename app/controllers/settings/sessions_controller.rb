module Settings
  class SessionsController < ApplicationController
    layout "settings"

    def index
      @sessions = Current.user.sessions.active.order(last_active_at: :desc)
      # Capped at 10: a security-context aid on the devices page, not a full
      # audit log. `.load` avoids the view's `.any?` issuing a separate EXISTS
      # query ahead of the `.each` SELECT — this page renders on every visit.
      @recent_activity = ActivityLog.security_events_for(Current.user).limit(10).load
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
