require "rails_helper"

RSpec.describe "Settings::Sessions", type: :request do
  let(:user) { create(:user, password: "SecureP@ssw0rd123!") }

  # The session backing the request's cookie is the one sign_in created — the
  # only session that exists at that point. Capture it before tests add more.
  before do
    sign_in(user)
    @current = user.sessions.sole
  end

  describe "GET /settings/sessions" do
    it "lists the user's active sessions and marks the current device" do
      get settings_sessions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings.sessions.index.current_device"))
    end

    it "excludes expired sessions" do
      stale = user.sessions.create!(user_agent: "Old", ip_address: "10.0.0.9")
      stale.update_columns(last_active_at: (Session.idle_timeout + 1.day).ago)
      get settings_sessions_path
      expect(response.body).not_to include("10.0.0.9")
    end

    it "does not show another user's sessions" do
      other = create(:user)
      other.sessions.create!(user_agent: "Intruder", ip_address: "10.9.9.9")
      get settings_sessions_path
      expect(response.body).not_to include("10.9.9.9")
    end
  end

  describe "DELETE /settings/sessions/:id" do
    it "revokes a chosen other session" do
      other = user.sessions.create!(user_agent: "Other", ip_address: "10.0.0.2")
      delete settings_session_path(other)
      expect(Session.exists?(other.id)).to be(false)
      expect(response).to redirect_to(settings_sessions_path)
      follow_redirect!
      expect(flash[:notice]).to eq(I18n.t("settings.sessions.destroy.signed_out", device: other.device_label))
    end

    it "cannot revoke another user's session" do
      other_user = create(:user)
      victim = other_user.sessions.create!(user_agent: "Victim", ip_address: "10.0.0.3")
      delete settings_session_path(victim)
      expect(response).to have_http_status(:redirect)
      expect(Session.exists?(victim.id)).to be(true)
    end

    it "signs the user out when revoking the current session" do
      delete settings_session_path(@current)
      expect(response).to redirect_to(new_session_path)
      follow_redirect!
      expect(flash[:notice]).to eq(I18n.t("settings.sessions.destroy.signed_out_current"))
    end
  end

  describe "DELETE /settings/other_sessions" do
    it "revokes all sessions except the current one" do
      user.sessions.create!(user_agent: "A", ip_address: "10.0.0.4")
      user.sessions.create!(user_agent: "B", ip_address: "10.0.0.5")

      delete settings_other_sessions_path
      expect(user.sessions.pluck(:id)).to eq([ @current.id ])
      expect(response).to redirect_to(settings_sessions_path)
      follow_redirect!
      expect(flash[:notice]).to eq(I18n.t("settings.other_sessions.destroy.signed_out", count: 2))
    end
  end

  describe "credential change invalidates other sessions" do
    it "password update revokes other sessions but keeps the current one" do
      other = user.sessions.create!(user_agent: "Other", ip_address: "10.0.0.6")

      patch settings_password_path, params: { user: { password: "N3wP@ssw0rd!x", password_confirmation: "N3wP@ssw0rd!x" } }

      expect(Session.exists?(other.id)).to be(false)
      expect(Session.exists?(@current.id)).to be(true)
    end
  end
end
