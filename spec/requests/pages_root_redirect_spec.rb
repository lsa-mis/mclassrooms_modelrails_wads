require "rails_helper"

# MiClassrooms Phase 3 Task 6 (Brief §5.1): signed-in non-admins land on
# Find a Room instead of the marketing homepage; admins and anonymous
# visitors keep the landing page. `pages#home` only redirects when the
# shared workspace is admittable (kept + not suspended) — the same gate
# DirectoryScoped uses to admit GET /find-a-room — so a suspended shared
# workspace can never bounce a viewer in an infinite root <-> find-a-room
# loop. Same stubbing pattern as spec/requests/rooms_spec.rb.
RSpec.describe "GET / redirect for signed-in non-admins", type: :request do
  let(:workspace) { create(:workspace, slug: "pages-root-redirect-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # `create(:user)` triggers User#onboard_workspace (after_create), which —
  # under the :shared posture stubbed above — auto-joins `workspace` with
  # TenancyConfig.shared_join_role before this method ever runs. Creating a
  # second Membership for the same (user, workspace) pair would violate the
  # user_id/workspace_id uniqueness index, so this reuses and re-roles the
  # auto-created membership instead of inserting a new one.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  describe "anonymous" do
    it "renders the landing page, no redirect" do
      get root_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "signed-in viewer with an admittable shared workspace" do
    let(:viewer) { membership_with("viewer") }

    it "redirects to Find a Room" do
      sign_in(viewer)

      get root_path

      expect(response).to redirect_to(find_a_room_path)
    end
  end

  describe "signed-in admin" do
    let(:admin) { membership_with("admin") }

    it "renders the landing page, no redirect" do
      sign_in(admin)

      get root_path

      expect(response).to have_http_status(:ok)
    end
  end

  # Loop-guard teeth: without the `!workspace.suspended?` check, a viewer
  # would bounce / -> find_a_room -> root_path (DirectoryScoped redirects a
  # suspended workspace back to root) -> find_a_room -> ... forever. This
  # example fails without the suspended? guard in PagesController#home.
  describe "signed-in viewer whose shared workspace is suspended" do
    let(:viewer) { membership_with("viewer") }

    it "renders the landing page instead of redirecting into the loop" do
      # Join the (still-admittable) workspace first, then suspend it — mirrors
      # the real sequence (a viewer joins, the workspace is suspended later).
      # Suspending before membership_with would make join_shared_workspace's
      # own admittable? guard skip creating the membership entirely.
      sign_in(viewer)
      workspace.update!(suspended_at: Time.current)

      get root_path

      expect(response).to have_http_status(:ok)
      expect(response).not_to redirect_to(find_a_room_path)
    end
  end
end
