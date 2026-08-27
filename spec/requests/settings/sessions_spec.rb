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

    it "renders inside the settings shell with the identity sidebar" do
      get settings_sessions_path
      aside = Nokogiri::HTML(response.body).at_css(
        %(aside[aria-label="#{I18n.t("settings.sidebar.aria_label")}"])
      )
      expect(aside).not_to be_nil
      expect(aside.at_css(%(a[href="#{settings_sessions_path}"]))).not_to be_nil
    end

    it "renders the current-device pill through UI::Badge, preserving the aria-hidden/sr-only pairing" do
      get settings_sessions_path

      html = Capybara.string(response.body)
      expect(html).to have_css("span[data-variant='soft'][data-tone='success'][aria-hidden='true']",
        exact_text: I18n.t("settings.sessions.index.current_device"))
      # Guard (green before and after): the visible pill is decorative; the sr-only
      # sibling carries the announcement.
      expect(html).to have_css("span.sr-only",
        text: I18n.t("settings.sessions.index.current_device"), visible: :all)
    end
  end

  describe "modal id uniqueness (#685)" do
    it "renders per-row confirm dialogs without duplicate element ids" do
      3.times { |n| user.sessions.create!(user_agent: "Agent #{n}", ip_address: "10.0.0.#{n}") }

      get settings_sessions_path

      ids = Nokogiri::HTML(response.body).css("[id]").map { |el| el["id"] }
      duplicates = ids.tally.select { |_id, count| count > 1 }.keys
      expect(duplicates).to be_empty,
        "duplicate element ids on sessions index: #{duplicates.inspect}"
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

  describe "recent account activity card" do
    # sign_in above goes through the real controller (`user` has a password),
    # which itself writes a "user.signed_in_new_device" personal row (every
    # request-spec sign-in looks like a new device with no prior cookie).
    # Clear it so each example's fixtures are the only personal rows in play.
    before { ActivityLog.delete_all }

    def activity_items(body)
      Nokogiri::HTML(body).css("[data-testid='account-activity-item']")
    end

    # The label half of a row, with the timestamp removed — so an assertion
    # about what the label says cannot be satisfied by text from the <time>.
    def activity_label(row)
      row = row.dup
      row.css("time").remove
      row.text.strip
    end

    it "lists the user's personal rows newest first, capped at 10" do
      # 12 rows an hour apart: the oldest 2 must be excluded, and the
      # remaining 10 must render in descending time order — not merely
      # "10 rows", which a bug like `.limit(10)` without `.order` would
      # also satisfy.
      timestamps = 12.times.map { |i| (12 - i).hours.ago }
      timestamps.each do |t|
        travel_to(t) do
          create(:activity_log, :security, action: "user.password_changed", actor: user)
        end
      end

      get settings_sessions_path

      rows = activity_items(response.body)
      expect(rows.length).to eq(10)

      # iso8601 with no explicit precision renders whole seconds, so compare
      # at that grain rather than against the fixtures' sub-second `Time`s.
      rendered_epochs = rows.css("time").map { |el| Time.iso8601(el["datetime"]).to_i }
      expect(rendered_epochs).to eq(timestamps.sort.reverse.first(10).map(&:to_i))
      expect(rows.first.text).to include(I18n.t("settings.sessions.activity.user.password_changed"))
    end

    it "excludes another user's personal rows" do
      other_user = create(:user)
      create(:activity_log, :security, action: "user.password_changed", actor: other_user)

      get settings_sessions_path

      expect(activity_items(response.body)).to be_empty
    end

    # The card keys off SECURITY_ACTIONS membership, never off `personal`
    # visibility (#827). `Trackable#activity_visibility` is an overridable
    # seam — Membership already returns "admin" through it — so a fork
    # returning "personal" for a domain event would otherwise render arbitrary
    # rows under a heading whose empty state reads "No security events
    # recorded yet".
    it "excludes personal-visibility rows whose action is not a security action" do
      create(:activity_log, :security, action: "workspace.updated", actor: user)

      get settings_sessions_path

      expect(activity_items(response.body)).to be_empty
    end

    it "excludes workspace-visibility rows, even ones tracking the signed-in user" do
      create(:activity_log, action: "workspace.updated", trackable: user.personal_workspace,
                             workspace: user.personal_workspace, visibility: "workspace")
      create(:activity_log, :security, action: "user.password_changed", actor: user, visibility: "workspace")

      get settings_sessions_path

      expect(activity_items(response.body)).to be_empty
    end

    it "shows the empty state when the user has no personal rows" do
      get settings_sessions_path

      expect(activity_items(response.body)).to be_empty
      expect(response.body).to include(I18n.t("settings.sessions.activity.empty"))
    end

    # The fallback's real case is a NEW MEMBER of SECURITY_ACTIONS shipped
    # without a locale key — a non-member no longer reaches the card at all
    # now that membership is the filter (#827). stub_const puts the action in
    # the set the way a later PR in this arc would.
    it "degrades a future security action without a label to a humanized fallback" do
      stub_const("ActivityLog::SECURITY_ACTIONS", ActivityLog::SECURITY_ACTIONS + [ "user.mystery_action" ])
      create(:activity_log, :security, action: "user.mystery_action", actor: user)

      get settings_sessions_path

      row = activity_items(response.body).first
      expect(row.text).to include("Mystery action")
    end

    # Three reviewers, independently: "about 5 hours ago" is not enough to
    # decide whether an unfamiliar sign-in was yours. The exact moment was
    # already sitting in the `datetime` attribute, machine-readable and shown
    # to nobody. `title` surfaces it without displacing the scannable
    # relative text.
    #
    # Tokyo is deliberate: 21:30 UTC is 06:30 the NEXT DAY there, so ignoring
    # the user's timezone fails on the date and the hour, not merely on the
    # zone suffix.
    it "carries the exact moment, in the user's timezone, as the time's title" do
      user.create_preferences!(timezone: "Asia/Tokyo")

      travel_to(Time.utc(2026, 8, 26, 21, 30)) do
        create(:activity_log, :security, action: "user.password_changed", actor: user)
      end

      get settings_sessions_path

      expect(activity_items(response.body).first.at_css("time")["title"])
        .to eq("August 27, 2026 at 6:30 AM JST")
    end

    # #832 — the OS on a new-device sign-in is the ONE metadata field that
    # renders. "Signed in from a new device" alone gives a user nothing to
    # recognise or disown; naming the platform is what makes the row
    # actionable. The value is one of six literals the user-agent parser
    # emits, never free text and never attacker-chosen.
    it "names the OS on a new-device sign-in" do
      create(:activity_log, :security, action: "user.signed_in_new_device", actor: user,
                             metadata: { os: "Windows" })

      get settings_sessions_path

      expect(activity_label(activity_items(response.body).first))
        .to eq("Signed in from a new device (Windows)")
    end

    # Rows written before the OS was captured, and any fork whose parser
    # returns nothing, still have to read as a sentence.
    it "falls back to the bare label for a device row with no OS recorded" do
      create(:activity_log, :security, action: "user.signed_in_new_device", actor: user, metadata: {})

      get settings_sessions_path

      expect(activity_label(activity_items(response.body).first))
        .to eq(I18n.t("settings.sessions.activity.user.signed_in_new_device"))
    end

    # The exception is sanctioned by the LOCALE, not by the metadata: an
    # `os` key on an action whose label does not interpolate one renders
    # nothing extra. That is what keeps the nickname — user-supplied free
    # text — off the page without a second guard to remember.
    it "renders no metadata on actions whose label does not name any" do
      create(:activity_log, :security, action: "user.passkey_added", actor: user, metadata: { os: "macOS", nickname: "Dave's laptop" })

      get settings_sessions_path

      # Through the parsed row, not the raw body: ERB escapes the apostrophe to
      # &#39;, so a raw-body include("Dave's laptop") could never fail even if
      # the view did render the nickname. Equality, not include, so anything
      # appended to the label fails.
      expect(activity_label(activity_items(response.body).first))
        .to eq(I18n.t("settings.sessions.activity.user.passkey_added"))
    end
  end
end
