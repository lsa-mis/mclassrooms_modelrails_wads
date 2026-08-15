require "rails_helper"

RSpec.describe Session, type: :model do
  let(:idle) { Rails.configuration.x.session.idle_timeout }
  let(:absolute) { Rails.configuration.x.session.absolute_timeout }
  let(:throttle) { Rails.configuration.x.session.touch_throttle }

  def build_session(created_at:, last_active_at:)
    user = create(:user)
    user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1").tap do |s|
      s.update_columns(created_at: created_at, last_active_at: last_active_at)
    end
  end

  describe "#expired?" do
    it "is false for a fresh session" do
      freeze_time do
        expect(build_session(created_at: Time.current, last_active_at: Time.current)).not_to be_expired
      end
    end

    it "is true when idle beyond the idle timeout" do
      freeze_time do
        s = build_session(created_at: 1.hour.ago, last_active_at: idle.ago - 1.second)
        expect(s).to be_expired
      end
    end

    it "is true past the absolute timeout even when recently active" do
      freeze_time do
        s = build_session(created_at: absolute.ago - 1.second, last_active_at: Time.current)
        expect(s).to be_expired
      end
    end

    it "treats a nil last_active_at as created_at (nil-safe)" do
      freeze_time do
        s = build_session(created_at: Time.current, last_active_at: nil)
        expect(s).not_to be_expired
      end
    end
  end

  describe "#touch_last_active!" do
    it "does not write within the throttle window" do
      s = build_session(created_at: Time.current, last_active_at: Time.current)
      original = s.reload.last_active_at
      s.touch_last_active!
      expect(s.reload.last_active_at).to eq(original)
    end

    it "advances last_active_at once past the throttle window" do
      s = build_session(created_at: 1.hour.ago, last_active_at: (throttle + 1.minute).ago)
      original = s.reload.last_active_at
      s.touch_last_active!
      expect(s.reload.last_active_at).to be > original
    end
  end

  describe "#reauthenticated? / #confirm_reauthentication!" do
    let(:session) { create(:user).sessions.create!(user_agent: "t", ip_address: "127.0.0.1") }

    it "is false with no reauthenticated_at" do
      expect(session.reauthenticated?).to be(false)
    end

    it "is true within the reauth window and false after" do
      session.confirm_reauthentication!
      expect(session.reload.reauthenticated?).to be(true)
      session.update_columns(reauthenticated_at: (Session.reauth_window + 1.minute).ago)
      expect(session.reload.reauthenticated?).to be(false)
    end

    it "is per-session — one session's reauth does not grant another's" do
      user = session.user
      other = user.sessions.create!(user_agent: "t2", ip_address: "127.0.0.2")
      session.confirm_reauthentication!
      expect(other.reload.reauthenticated?).to be(false)
    end
  end

  describe "scopes" do
    it "partitions active and expired" do
      freeze_time do
        active = build_session(created_at: Time.current, last_active_at: Time.current)
        expired = build_session(created_at: 1.hour.ago, last_active_at: idle.ago - 1.second)
        expect(Session.active).to include(active)
        expect(Session.active).not_to include(expired)
        expect(Session.expired).to include(expired)
        expect(Session.expired).not_to include(active)
      end
    end
  end
end
