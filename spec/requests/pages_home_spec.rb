require "rails_helper"

# Panel call (2026-07-13): GET / renders the landing page for EVERYONE —
# anonymous, viewer, admin. The header logo links to root, and a link named
# for the site must mean the same thing for every role, so the old
# Phase 3 Task 6 non-admin redirect (pinned by this file's predecessor,
# pages_root_redirect_spec.rb) is retired. "Signed-in users start in the
# product" moved to the sign-in moment — see
# spec/requests/authenticated_home_override_spec.rb. Rendering for viewers
# also un-hides the home_page announcement slot they previously could never
# reach; the view swaps sign-in CTAs for Find-a-Room ones when authenticated.
RSpec.describe "GET / landing page", type: :request do
  let(:workspace) { create(:workspace, slug: "pages-home-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # `create(:user)` auto-joins `workspace` via User#onboard_workspace under
  # the :shared posture stubbed above — re-role the auto-created membership
  # (mirrors spec/requests/rooms_spec.rb).
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  def page = Capybara.string(response.body)

  it "renders for anonymous visitors with sign-in CTAs" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(page).to have_link(I18n.t("pages.home.hero.cta_primary"), href: new_session_path)
  end

  it "renders for a signed-in viewer — no redirect — with CTAs into the product" do
    sign_in(membership_with("viewer"))

    get root_path

    expect(response).to have_http_status(:ok)
    expect(page).to have_link(I18n.t("pages.home.hero.cta_primary_signed_in"), href: find_a_room_path)
    expect(page).to have_link(I18n.t("pages.home.cta.button_signed_in"), href: find_a_room_path)
    expect(page).to have_no_link(href: new_session_path)
  end

  it "renders for a signed-in admin, same page as everyone" do
    sign_in(membership_with("admin"))

    get root_path

    expect(response).to have_http_status(:ok)
  end
end
