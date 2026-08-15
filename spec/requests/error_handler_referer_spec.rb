# frozen_string_literal: true

require "rails_helper"

# SEC-10: the global 403/404 handlers redirected to raw `request.referer`.
# With `raise_on_open_redirects` (on by default), a FORGED cross-origin
# Referer header made the error handler itself raise UnsafeRedirectError —
# a 500 from the code whose one job is rendering errors gracefully.
# `url_from` filters the referer to same-origin and falls back to root.
RSpec.describe "Error-handler referer redirects (SEC-10)", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  # Trigger: a session id that isn't the user's reaches the GLOBAL handler —
  # the workspace/project controllers rescue their own 404s with friendlier
  # redirects and never get here.
  describe "record_not_found (404 handler)" do
    it "falls back to root for a forged cross-origin referer instead of 500ing" do
      delete settings_session_path(999_999), headers: { "Referer" => "https://evil.example/phish" }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
    end

    it "still returns the user to a same-origin referer" do
      delete settings_session_path(999_999),
             headers: { "Referer" => "http://www.example.com/settings/sessions" }

      expect(response).to redirect_to("http://www.example.com/settings/sessions")
    end
  end
end
