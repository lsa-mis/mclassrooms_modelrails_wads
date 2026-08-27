# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityLogRetentionSweepJob, type: :job do
  it "deletes activity older than the retention window" do
    stale = create(:activity_log, created_at: (described_class::RETENTION_WINDOW + 1.day).ago)

    described_class.perform_now

    expect(ActivityLog.exists?(stale.id)).to be(false)
  end

  it "keeps activity inside the window, right up to the boundary" do
    recent = create(:activity_log, created_at: 1.day.ago)
    near_boundary = create(:activity_log, created_at: (described_class::RETENTION_WINDOW - 1.day).ago)

    described_class.perform_now

    expect(ActivityLog.exists?(recent.id)).to be(true)
    expect(ActivityLog.exists?(near_boundary.id)).to be(true)
  end

  describe "security retention floor" do
    let(:user) { create(:user) }

    def personal_row(action, age)
      user # materialize before the warp — records created inside travel_to land at the travelled-to timestamp (R7, #830)
      travel_to(age.ago) do
        create(:activity_log, :security, action: action, actor: user)
      end
    end

    # 12.months.ago and 365.days.ago land on the same calendar day (Duration#ago
    # is calendar-aware, not seconds-based), so the brief's original 364-day
    # example was a zero-width band that couldn't fail. Shrinking the general
    # window for this example is what makes it sensitive to the floor.
    it "keeps security rows older than the general window but younger than the floor" do
      stub_const("ActivityLogRetentionSweepJob::RETENTION_WINDOW", 30.days)
      kept = personal_row("user.password_changed", 60.days)
      swept = travel_to(60.days.ago) do
        ActivityLog.create!(action: "workspace.updated", trackable: create(:workspace))
      end

      described_class.perform_now

      expect(ActivityLog.exists?(kept.id)).to be(true)
      expect(ActivityLog.exists?(swept.id)).to be(false)
    end

    # A floor that deletes what the general window keeps is not a floor. The two
    # constants are equal in an ordinary year, but 12.months.ago is calendar-aware
    # and reaches a day FURTHER back than 365.days.ago whenever the window spans a
    # Feb 29 — inverting them for roughly one year in four. Lengthening the general
    # window here reproduces that inversion deterministically, at a scale a
    # date-dependent example could not.
    it "never deletes a security row the general window would keep" do
      stub_const("ActivityLogRetentionSweepJob::RETENTION_WINDOW", 400.days)
      security = personal_row("user.password_changed", 380.days)
      ordinary = travel_to(380.days.ago) do
        ActivityLog.create!(action: "workspace.updated", trackable: create(:workspace))
      end

      described_class.perform_now

      expect(ActivityLog.exists?(ordinary.id)).to be(true) # the general window keeps it
      expect(ActivityLog.exists?(security.id)).to be(true) # so the floor must too
    end

    it "deletes security rows older than the floor" do
      doomed = personal_row("user.password_changed", 370.days)
      described_class.perform_now
      expect(ActivityLog.exists?(doomed.id)).to be(false)
    end

    it "still deletes non-security rows on the 12-month window" do
      doomed = travel_to(13.months.ago) do
        ActivityLog.create!(action: "workspace.updated", trackable: create(:workspace))
      end
      described_class.perform_now
      expect(ActivityLog.exists?(doomed.id)).to be(false)
    end

    it "exempts by membership in ActivityLog::SECURITY_ACTIONS, not by visibility" do
      admin_row = travel_to(13.months.ago) do
        ActivityLog.create!(action: "invitation.suppressed_delivery", trackable: user, visibility: "admin")
      end
      described_class.perform_now
      expect(ActivityLog.exists?(admin_row.id)).to be(false)
    end
  end
end
