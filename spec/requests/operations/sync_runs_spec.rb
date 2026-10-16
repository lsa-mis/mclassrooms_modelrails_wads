require "rails_helper"

RSpec.describe "Operations sync runs", type: :request do
  include ActiveJob::TestHelper

  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }
  let(:workspace) { create(:workspace, slug: "ops-sync-workspace", personal: false) }

  def failed_run = create(:sync_run, workspace:, status: :failed, started_at: 1.hour.ago, finished_at: 50.minutes.ago)

  before do
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    sign_in(operator)
  end

  describe "GET /operations/sync_runs" do
    it "shows the history with run-now and retry controls" do
      failed = failed_run
      create(:sync_run, status: :failed, started_at: 1.hour.ago)

      get operations_sync_runs_path

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("[data-sync-run-history] tbody tr", count: 1)
      expect(page).to have_button(I18n.t("operations.sync_runs.actions.run_now"))
      expect(page).to have_css("form[action='#{operations_sync_run_resumption_path(failed)}']")
    end

    it "offers Retry only on the most recent run" do
      older = failed_run
      newest = create(:sync_run, workspace:, status: :failed, started_at: 10.minutes.ago, finished_at: 5.minutes.ago)

      get operations_sync_runs_path

      expect(page).to have_css("form[action='#{operations_sync_run_resumption_path(newest)}']")
      expect(page).to have_no_css("form[action='#{operations_sync_run_resumption_path(older)}']")
    end

    it "is listed last in the operations nav, marked as the current page" do
      get operations_sync_runs_path

      links = page.all("nav[aria-label='#{I18n.t('operations.area.nav_label')}'] a")
      expect(links.last.text).to eq(I18n.t("operations.nav.sync_runs"))
      expect(links.last[:"aria-current"]).to eq("page")
    end

    it "says a sync is running, and still offers Run now in case that run was left by a stopped worker" do
      create(:sync_run, workspace:, status: :running, started_at: 1.minute.ago)

      get operations_sync_runs_path

      expect(page).to have_text(I18n.t("operations.sync_runs.index.running_notice"))
      expect(page).to have_button(I18n.t("operations.sync_runs.actions.run_now"))
    end

    it "shows a running sync's step, a progress bar and the usual duration, and subscribes to live updates" do
      create(:sync_run, workspace:, status: :succeeded, started_at: 1.day.ago, finished_at: 1.day.ago + 14.minutes)
      run = create(:sync_run, workspace:, status: :running, started_at: 3.minutes.ago)
      create(:sync_phase, sync_run: run, key: "campuses", status: :succeeded)
      create(:sync_phase, sync_run: run, key: "buildings", status: :running)

      get operations_sync_runs_path

      progress = page.find("[data-sync-progress]")
      expect(progress).to have_text("Step 2 of 6: #{I18n.t("sync_runs.phases.buildings")}")
      expect(progress).to have_css('[role="progressbar"][aria-valuenow="16"][aria-valuemax="100"]')
      expect(progress).to have_text(I18n.t("sync_runs.progress.typical", duration: "14 minutes"))
      expect(page).to have_css("turbo-cable-stream-source", visible: :all)
      expect(page).to have_css('meta[name="turbo-refresh-method"][content="morph"]', visible: :all)
    end

    it "shows how far the running step has got, and each run's change count" do
      create(:sync_run, workspace:, status: :succeeded, started_at: 1.day.ago, finished_at: 1.day.ago + 14.minutes)
      run = create(:sync_run, workspace:, status: :running, started_at: 6.minutes.ago)
      create(:sync_phase, sync_run: run, key: "rooms", status: :succeeded, counters: { "updated" => 1_204, "api_calls" => 161 })
      create(:sync_phase, sync_run: run, key: "facility_ids", status: :running, items_done: 612, items_total: 1_067)

      get operations_sync_runs_path

      expect(page.find("[data-sync-progress]")).to have_text("612 of 1,067 facilities")
      history = page.find("[data-sync-run-history]")
      expect(history).to have_css("tr", text: "1,204 changes")
      expect(history).to have_css("tr", text: I18n.t("sync_runs.changes.total.none"))
    end
  end

  describe "GET /operations/sync_runs/:id" do
    it "shows a failed run's phases with a retry control" do
      run = failed_run
      create(:sync_phase, sync_run: run, key: "rooms", status: :failed, error_messages: [ "gateway timed out" ])

      get operations_sync_run_path(run)

      expect(page).to have_css("[data-sync-phase]", text: "gateway timed out")
      expect(page).to have_button(I18n.t("operations.sync_runs.actions.retry"))
    end

    it "lists what a finished sync changed" do
      run = create(:sync_run, workspace:, status: :succeeded, started_at: 1.hour.ago, finished_at: 50.minutes.ago)
      create(:sync_phase, sync_run: run, key: "rooms", status: :succeeded, counters: { "created" => 1, "updated" => 3, "api_calls" => 161 })
      create(:sync_phase, sync_run: run, key: "contacts", status: :succeeded, counters: { "updated" => 1 })

      get operations_sync_run_path(run)

      changes = page.find("[data-sync-changes]")
      expect(changes).to have_css("h2", text: I18n.t("sync_runs.changes.heading.finished"))
      expect(changes.all("li").map(&:text)).to eq([ "1 room added", "3 rooms updated", "1 room contact updated" ])
    end

    it "says when a finished sync changed nothing, and that a dry run's changes are hypothetical" do
      real = create(:sync_run, workspace:, status: :succeeded, started_at: 2.hours.ago, finished_at: 110.minutes.ago)
      create(:sync_phase, sync_run: real, key: "rooms", status: :succeeded, counters: { "api_calls" => 161 })
      dry = create(:sync_run, workspace:, status: :succeeded, dry_run: true, started_at: 1.hour.ago, finished_at: 50.minutes.ago)
      create(:sync_phase, sync_run: dry, key: "rooms", status: :succeeded, counters: { "deactivated" => 2 })

      get operations_sync_run_path(real)
      expect(page.find("[data-sync-changes]")).to have_text(I18n.t("sync_runs.changes.none.matched"))

      get operations_sync_run_path(dry)
      changes = page.find("[data-sync-changes]")
      expect(changes).to have_css("h2", text: I18n.t("sync_runs.changes.heading.dry_run"))
      expect(changes).to have_text(I18n.t("sync_runs.changes.dry_run_note"))
      expect(changes).to have_css("li", text: "2 rooms deactivated")
    end

    it "does not show a run from a workspace other than the directory" do
      get operations_sync_run_path(create(:sync_run))

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
    end
  end

describe "POST /operations/sync_runs" do
  it "requests the directory sync for this operator" do
    allow(SyncRunJob).to receive(:request).and_return(:queued)

    post operations_sync_runs_path

    expect(response).to redirect_to(operations_sync_runs_path)
    expect(flash[:notice]).to eq(I18n.t("operations.sync_runs.create.success"))
    expect(SyncRunJob).to have_received(:request).with(workspace, requested_by: operator)
  end

  it "says nothing new started when a sync is already queued or running" do
    allow(SyncRunJob).to receive(:request).and_return(:already_running)

    post operations_sync_runs_path

    expect(flash[:alert]).to eq(I18n.t("operations.sync_runs.already_running"))
  end

  it "says so when the job cannot be queued" do
    allow(SyncRunJob).to receive(:request).and_return(:not_queued)

    post operations_sync_runs_path

    expect(flash[:alert]).to eq(I18n.t("operations.sync_runs.not_queued"))
  end
end

describe "POST /operations/sync_runs/:id/resumption" do
  it "requests a retry of the most recent failed run" do
    run = failed_run
    allow(SyncRunJob).to receive(:request).and_return(:queued)

    post operations_sync_run_resumption_path(run)

    expect(response).to redirect_to(operations_sync_run_path(run))
    expect(flash[:notice]).to eq(I18n.t("operations.sync_runs.resumptions.create.success"))
    expect(SyncRunJob).to have_received(:request).with(workspace, resume: run, requested_by: operator)
  end

  it "refuses a run that is not the most recent, or did not fail" do
    older = failed_run
    create(:sync_run, workspace:, status: :succeeded, started_at: 10.minutes.ago, finished_at: 5.minutes.ago)
    allow(SyncRunJob).to receive(:request)

    post operations_sync_run_resumption_path(older)

    expect(flash[:alert]).to eq(I18n.t("operations.sync_runs.resumptions.create.not_resumable"))
    expect(SyncRunJob).not_to have_received(:request)
  end

  it "says nothing new started when a sync is already queued or running" do
    run = failed_run
    allow(SyncRunJob).to receive(:request).and_return(:already_running)

    post operations_sync_run_resumption_path(run)

    expect(flash[:alert]).to eq(I18n.t("operations.sync_runs.already_running"))
  end

  it "says so when the retry cannot be queued" do
    run = failed_run
    allow(SyncRunJob).to receive(:request).and_return(:not_queued)

    post operations_sync_run_resumption_path(run)

    expect(flash[:alert]).to eq(I18n.t("operations.sync_runs.not_queued"))
  end
end

  it "lists both operator actions in the activity ledger under their own kind" do
    allow(Sync::RunPipeline).to receive(:call) { |run:| run }
    SyncRunJob.perform_now(workspace, resume: failed_run, requested_by: operator)
    SyncRunJob.perform_now(workspace, requested_by: operator)

    get operations_activity_logs_path(kind: "sync_run")

    expect(response).to have_http_status(:ok)
    expect(page).to have_text(I18n.t("activity.actions.sync_run.requested"))
    expect(page).to have_text(I18n.t("activity.actions.sync_run.resumed"))
  end
end
