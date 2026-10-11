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

    it "says a sync is running, and still offers Run now in case that run was left by a stopped worker" do
      create(:sync_run, workspace:, status: :running, started_at: 1.minute.ago)

      get operations_sync_runs_path

      expect(page).to have_text(I18n.t("operations.sync_runs.index.running_notice"))
      expect(page).to have_button(I18n.t("operations.sync_runs.actions.run_now"))
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

    it "does not show a run from a workspace other than the directory" do
      get operations_sync_run_path(create(:sync_run))

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
    end
  end

  describe "POST /operations/sync_runs" do
    it "enqueues the directory's sync for this operator" do
      post operations_sync_runs_path

      expect(response).to redirect_to(operations_sync_runs_path)
      expect(flash[:notice]).to eq(I18n.t("operations.sync_runs.create.success"))
      expect(SyncRunJob).to have_been_enqueued.with(workspace, requested_by: operator)
    end

    it "says so when the job cannot be queued" do
      allow(SyncRunJob).to receive(:perform_later).and_return(false)

      post operations_sync_runs_path

      expect(flash[:alert]).to eq(I18n.t("operations.sync_runs.not_queued"))
    end
  end

  describe "POST /operations/sync_runs/:id/resumption" do
    it "enqueues a retry of a failed run" do
      run = failed_run

      post operations_sync_run_resumption_path(run)

      expect(response).to redirect_to(operations_sync_run_path(run))
      expect(flash[:notice]).to eq(I18n.t("operations.sync_runs.resumptions.create.success"))
      expect(SyncRunJob).to have_been_enqueued.with(workspace, resume: run, requested_by: operator)
    end

    it "refuses a run that did not fail" do
      run = create(:sync_run, workspace:, status: :succeeded, started_at: 1.hour.ago, finished_at: 50.minutes.ago)

      post operations_sync_run_resumption_path(run)

      expect(flash[:alert]).to eq(I18n.t("operations.sync_runs.resumptions.create.not_resumable"))
      expect(SyncRunJob).not_to have_been_enqueued
    end

    it "says so when the retry cannot be queued" do
      run = failed_run
      allow(SyncRunJob).to receive(:perform_later).and_return(false)

      post operations_sync_run_resumption_path(run)

      expect(flash[:alert]).to eq(I18n.t("operations.sync_runs.not_queued"))
    end
  end

  # Upstream's ledger has never seen these fork rows, so read it with them in place.
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
