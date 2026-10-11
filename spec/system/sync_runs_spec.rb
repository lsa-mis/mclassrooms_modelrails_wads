require "rails_helper"

RSpec.describe "Sync runs", type: :system do
  let!(:workspace) { create(:workspace, slug: "sync-runs-system", personal: false) }
  let!(:unit) { create(:unit, workspace:) }
  let!(:succeeded) do
    create(:sync_run, workspace:, status: :succeeded, started_at: 1.day.ago, finished_at: 1.day.ago + 18.minutes).tap do |run|
      SyncPhase::KEYS.first(6).each do |key|
        create(:sync_phase, sync_run: run, key:, status: :succeeded, started_at: run.started_at, finished_at: run.finished_at,
                            counters: { "created" => 2, "updated" => 40, "api_calls" => 12 })
      end
    end
  end
  let!(:failed) do
    create(:sync_run, workspace:, status: :failed, started_at: 2.hours.ago, finished_at: 2.hours.ago + 9.minutes).tap do |run|
      create(:sync_phase, sync_run: run, key: "campuses", status: :succeeded, counters: { "updated" => 3 })
      create(:sync_phase, sync_run: run, key: "buildings", status: :failed, error_messages: [ "Gateway timed out after 3 retries" ],
                          warnings: [ "Building 1005058 has no address" ])
      create(:sync_phase, sync_run: run, key: "rooms", status: :skipped)
    end
  end

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  it "lets an editor read the history and a failed run's errors, with no controls, at AAA in both themes" do
    sign_in_via_form(create(:user).tap { |user| create(:editor_assignment, user:, unit:) })

    visit admin_sync_runs_path
    expect(page).to have_css("[data-sync-run-history] tbody tr", count: 2)
    expect(page).to have_no_button(I18n.t("operations.sync_runs.actions.retry"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    click_link href: admin_sync_run_path(failed)
    expect(page).to have_css("[data-sync-phase]", text: "Gateway timed out after 3 retries")
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end

  # SyncRunJob.request is stubbed: the test adapter never sets provider_job_id, so every real request would read as dropped.
  it "lets an operator retry the most recent failed run and start a new one, at AAA in both themes" do
    allow(SyncRunJob).to receive(:request).and_return(:queued)
    sign_in_via_form(create(:user).tap { |user| Operatorship.grant!(user:) })

    visit operations_sync_runs_path
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    click_link href: operations_sync_run_path(failed)
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
    click_button I18n.t("operations.sync_runs.actions.retry")
    expect(page).to have_text(I18n.t("operations.sync_runs.resumptions.create.success"))

    visit operations_sync_runs_path
    accept_confirm { click_button I18n.t("operations.sync_runs.actions.run_now") }
    expect(page).to have_text(I18n.t("operations.sync_runs.create.success"))
  end

  it "tells an operator a sync is running before they reach Run now, at AAA in both themes" do
    create(:sync_run, workspace:, status: :running, started_at: 5.minutes.ago)
    sign_in_via_form(create(:user).tap { |user| Operatorship.grant!(user:) })

    visit operations_sync_runs_path

    expect(page).to have_text(I18n.t("operations.sync_runs.index.running_notice"))
    expect(page.text.index(I18n.t("operations.sync_runs.index.running_notice")))
      .to be < page.text.index(I18n.t("operations.sync_runs.actions.run_now"))
    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
  end
end
