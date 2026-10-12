require "rails_helper"

RSpec.describe SyncRunsHelper do
  # Scans code, not comments: a counter a phase writes but the run page cannot label is a silent omission.
  it "labels every counter a sync phase writes" do
    written = Rails.root.glob("app/lib/sync/**/*.rb").flat_map do |path|
      path.readlines.reject { |line| line.strip.start_with?("#") }.join.scan(/\bcount\(:([a-z_]+)/).flatten
    end.uniq

    expect(written - SyncRunsHelper::COUNTERS).to be_empty
    SyncRunsHelper::COUNTERS.each { |key| expect(I18n.t("sync_runs.counters.#{key}")).to be_present }
  end

  describe "#sync_duration" do
    it "says how long a finished run took, in translated words" do
      run = build(:sync_run, status: :succeeded, started_at: 2.hours.ago, finished_at: 2.hours.ago + 1.hour + 5.minutes)

      expect(helper.sync_duration(run)).to eq("1 hour and 5 minutes")
    end

    it "says how long a running run has been going, so an operator can see it near the lock's limit" do
      run = build(:sync_run, status: :running, started_at: 2.hours.ago - 41.minutes)

      expect(helper.sync_duration(run)).to start_with("Running for 2 hours and 41 minutes")
    end

    it "says not finished for a run that never started" do
      expect(helper.sync_duration(build(:sync_phase, status: :pending))).to eq(I18n.t("sync_runs.not_finished"))
    end
  end
end
