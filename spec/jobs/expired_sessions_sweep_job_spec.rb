require "rails_helper"

RSpec.describe ExpiredSessionsSweepJob, type: :job do
  def session_for(user, last_active_at:, created_at: 1.hour.ago)
    user.sessions.create!(user_agent: "t", ip_address: "127.0.0.1")
        .tap { |s| s.update_columns(created_at: created_at, last_active_at: last_active_at) }
  end

  it "deletes expired sessions and keeps active ones" do
    user = create(:user)
    active = session_for(user, last_active_at: Time.current)
    idle_expired = session_for(user, last_active_at: (Session.idle_timeout + 1.day).ago)
    old_expired = session_for(user, last_active_at: Time.current, created_at: (Session.absolute_timeout + 1.day).ago)

    described_class.perform_now

    expect(Session.exists?(active.id)).to be(true)
    expect(Session.exists?(idle_expired.id)).to be(false)
    expect(Session.exists?(old_expired.id)).to be(false)
  end
end
