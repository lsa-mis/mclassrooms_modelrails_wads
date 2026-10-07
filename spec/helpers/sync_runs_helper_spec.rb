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
end
