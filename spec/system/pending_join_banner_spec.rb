require "rails_helper"

# FU-1: a logged-out visitor can be lured into POSTing an open-link join
# confirmation, which parks the token in the session. That token must never
# silently force-join whoever authenticates next — a pre-existing user who then
# signs in normally is offered an explicit Join / Dismiss banner instead.
RSpec.describe "Pending join banner (drive-by re-consent)", type: :system do
  let(:existing_user) { create(:user, first_name: "Ada", last_name: "Lovelace") }
  let(:join_workspace) { create(:workspace, name: "Lured Co", join_policy: "open_link") }
  let(:link) { create(:workspace_join_link, workspace: join_workspace) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    # Direct config mutation (not allow stubs) so the value is visible on the
    # Rack thread the browser hits, not just the test thread.
    @original_strategies = Rails.configuration.x.signup.permitted_join_strategies
    Rails.configuration.x.signup.permitted_join_strategies = [ :invite, :open_link ]
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }

    # Lure: park a pending join as a logged-out visitor, then sign in normally.
    visit workspace_join_path(join_workspace, token: link.plaintext_token)
    click_button I18n.t("workspaces.joins.show.join_button", workspace: join_workspace.name)
    expect(page).to have_text(I18n.t("sessions.new.title"))
    sign_in_via_form(existing_user)
  end

  after { Rails.configuration.x.signup.permitted_join_strategies = @original_strategies }

  it "does not auto-join, and offers an explicit Join / Dismiss banner" do
    expect(page).to have_css("#pending-join-banner")
    expect(page).to have_text(I18n.t("workspaces.pending_join_banner.message", workspace: join_workspace.name))
    expect(existing_user.memberships.kept.where(workspace: join_workspace)).not_to exist
  end

  it "Join admits the user and clears the banner" do
    within "#pending-join-banner" do
      click_button I18n.t("workspaces.pending_join_banner.join", workspace: join_workspace.name)
    end
    expect(page).not_to have_css("#pending-join-banner")
    expect(existing_user.memberships.kept.where(workspace: join_workspace)).to exist
  end

  it "Dismiss clears the banner without joining" do
    within "#pending-join-banner" do
      click_button I18n.t("workspaces.pending_join_banner.dismiss")
    end
    expect(page).not_to have_css("#pending-join-banner")
    expect(existing_user.memberships.kept.where(workspace: join_workspace)).not_to exist
  end

  it "banner is axe-clean at AAA (both themes)" do
    expect(page).to have_css("#pending-join-banner")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on pending-join banner: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
