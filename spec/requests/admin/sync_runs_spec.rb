require "rails_helper"

# Read-only sync history for the workspace's admins and editors; retry and run-now live in /operations.
RSpec.describe "Admin sync runs", type: :request do
  let(:workspace) { create(:workspace, slug: "sync-runs-workspace", personal: false) }
  let(:unit) { create(:unit, workspace:) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def run_with_phases(status:, started_at:, phases: {})
    create(:sync_run, workspace:, status:, started_at:, finished_at: (started_at + 20.minutes unless status == :running)).tap do |run|
      phases.each { |key, phase_status| create(:sync_phase, sync_run: run, key:, status: phase_status, counters: { "created" => 3, "api_calls" => 12 }) }
    end
  end

  describe "GET /admin/sync_runs" do
    it "shows an editor the latest run, the fourteen most recent runs, and the inventory, with no controls" do
      sign_in(editor_for(unit))
      16.times { |i| run_with_phases(status: :succeeded, started_at: (i + 1).days.ago) }
      run_with_phases(status: :failed, started_at: 1.hour.ago)
      create(:room, building: create(:building, workspace:), workspace:)

      get admin_sync_runs_path

      expect(response).to have_http_status(:ok)
      expect(page).to have_css("[data-sync-run-latest]", text: I18n.t("sync_runs.status.failed"))
      expect(page).to have_css("[data-sync-run-history] tbody tr", count: 14)
      expect(page).to have_css("[data-sync-inventory]", text: I18n.t("sync_runs.inventory.classrooms"))
      expect(page).to have_no_button(I18n.t("operations.sync_runs.actions.run_now"))
      expect(page).to have_no_button(I18n.t("operations.sync_runs.actions.retry"))
      expect(page).to have_no_link(href: operations_sync_runs_path)
    end

    it "points an operator who is also an admin to the controls" do
      admin = membership_with("admin")
      Operatorship.grant!(user: admin)
      sign_in(admin)

      get admin_sync_runs_path

      expect(page).to have_link(href: operations_sync_runs_path)
    end

    it "says so when no sync has run yet" do
      sign_in(membership_with("admin"))

      get admin_sync_runs_path

      expect(page).to have_text(I18n.t("sync_runs.history.empty"))
    end

    it "refuses a viewer" do
      sign_in(membership_with("viewer"))

      get admin_sync_runs_path

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
    end
  end

  describe "GET /admin/sync_runs/:id" do
    it "shows one card per phase in pipeline order" do
      sign_in(membership_with("admin"))
      run = run_with_phases(status: :failed, started_at: 1.hour.ago,
                            phases: { "rooms" => :failed, "campuses" => :succeeded, "buildings" => :succeeded })

      get admin_sync_run_path(run)

      headings = page.all("[data-sync-phase] h3").map(&:text)
      expect(headings).to eq(%w[campuses buildings rooms].map { |key| I18n.t("sync_runs.phases.#{key}") })
    end

    it "does not show another workspace's run" do
      sign_in(membership_with("admin"))

      get admin_sync_run_path(create(:sync_run))

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
    end
  end
end
