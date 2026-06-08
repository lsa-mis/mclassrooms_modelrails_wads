# frozen_string_literal: true

require "rails_helper"

# AAA proof for PAGINATION. The app paginates with Pagy's `@pagy.series_nav` (accessible markup),
# styled to the design system via app/assets/tailwind/application.css (.pagy.series-nav). Pagy's
# helper needs a live view context, so we prove it on the real workspaces/members page (which
# already renders shared/_pagination) with enough members to paginate (>20). NOTE: per-spec axe
# runs AA locally; the AAA 7:1 audit is the CI-only wcag2aaa hook.
RSpec.describe "Pagination accessibility (Pagy series_nav)", type: :system do
  let(:user) { create(:user, first_name: "Owner", last_name: "User", password: "SecureP@ssw0rd123!") }
  let(:workspace) { create(:workspace, max_members: 50) }
  let!(:owner_membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before do
    # Seed 25 additional members so the combined list (owner + members) exceeds the Pagy limit of
    # 20, forcing series_nav to render. The controller builds `combined = invitations + memberships`,
    # so total rows = 1 (owner) + 25 = 26 > 20.
    25.times do |i|
      member = create(:user, first_name: "Member", last_name: "#{i + 1}")
      create(:membership, user: member, workspace: workspace)
    end

    # Mirror members_table_spec.rb sign-in approach exactly.
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_css("#user-menu-button")

    visit workspace_members_path(workspace)
  end

  it "renders the Pagy series_nav on the members page and it passes AAA in both themes" do
    expect(page).to have_css("nav.pagy", wait: 5)
    expect(page).to have_css("[aria-current='page']")

    scope = [ "nav.pagy" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
