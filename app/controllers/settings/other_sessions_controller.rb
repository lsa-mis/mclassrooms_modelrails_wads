module Settings
  # "Sign out everywhere else" — revokes every session for the current user
  # except the one making this request. One statement, no per-row callbacks
  # (sessions have none), so it stays off the SQLite writer lock longer than a
  # destroy loop would.
  class OtherSessionsController < ApplicationController
    def destroy
      count = Current.user.sessions.where.not(id: Current.session.id).delete_all
      redirect_to settings_sessions_path, notice: t(".signed_out", count: count)
    end
  end
end
