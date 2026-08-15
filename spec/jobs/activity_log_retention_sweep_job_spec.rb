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
end
