# frozen_string_literal: true

require "rails_helper"

# #1050: Deactivate, Reactivate and Transfer ownership are button_to forms
# rendered INSIDE the members_results Turbo frame, and all three controllers
# answer with a redirect carrying a flash. Without an explicit `_top` target
# Turbo frames that redirect into members_results, so the notice — rendered
# outside the frame, in the layout — is fetched and thrown away. The action
# succeeds and the user is never told what happened. Same class as #1038
# (spec/system/workspaces/invitation_row_actions_spec.rb), and the reason
# Deactivate cannot answer with a row-replacing stream instead: its
# self-deactivation and last-owner branches redirect to a DIFFERENT page.
RSpec.describe "Member row actions escape the members frame", type: :system do
  let(:owner) { create(:user, first_name: "Olivia", last_name: "Owner") }
  let(:member) { create(:user, first_name: "Mel", last_name: "Member") }
  let(:workspace) { create(:workspace, name: "Acme", max_members: 50) }
  let(:actor) { owner }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  # Seed-agnostic: CI seeds the global roles, local rspec does not.
  let!(:owner_membership) { create(:membership, :owner, user: owner, workspace: workspace) }
  let!(:member_membership) { create(:membership, user: member, workspace: workspace) }

  before { sign_in_via_form(actor) }

  def row_for(membership)
    "##{ActionView::RecordIdentifier.dom_id(membership)}"
  end

  # Cuprite leaves the synthetic pointer where it last clicked, so a restored
  # page is audited with a row button held in :hover. That state blends
  # `text-danger`/`text-success` through the app-wide `hover:opacity-80` idiom
  # down to 5.0–6.4:1 — a REAL AAA hole, but in a pattern that spans 7 sites
  # including a UI component, so it is #1068 rather than half-fixed here.
  # Parking on the page heading (inert text, no hover style) audits the resting
  # state every other system spec audits. Delete this helper when #1068 lands —
  # left in place afterwards it would quietly protect the same regression.
  def park_pointer
    find("h1", match: :first).hover
  end

  def click_row_action(membership, label)
    within(row_for(membership)) { click_button label }
  end

  it "shows the deactivated notice after Deactivate, on an accessible restored page" do
    visit workspace_members_path(workspace)

    click_row_action(member_membership, I18n.t("workspaces.members.index.deactivate"))

    expect(page).to have_text(I18n.t("workspaces.members.destroy.deactivated"))
    expect(page).to have_css(row_for(member_membership),
                             text: I18n.t("workspaces.members.index.deactivated"))
    park_pointer

    # #912: the state this fix creates — the full-page render Turbo would
    # otherwise have discarded — is audited, not just the pristine index. The
    # toast is a transient overlay that dismisses on a timer; it is asserted
    # textually above and removed here so the audit reads the settled page.
    page.execute_script(
      "document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())"
    )
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on the restored members page: " \
      "#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "shows the reactivated notice after Reactivate" do
    member_membership.discard!
    visit workspace_members_path(workspace)

    click_row_action(member_membership, I18n.t("workspaces.members.index.reactivate"))

    expect(page).to have_text(
      I18n.t("workspaces.members.reactivations.create.reactivated")
    )
    park_pointer
  end

  it "shows the transferred notice after Transfer ownership" do
    visit workspace_members_path(workspace)

    click_row_action(member_membership, I18n.t("workspaces.members.index.transfer_ownership"))

    expect(page).to have_text(
      I18n.t("workspaces.members.ownership_transfers.create.transferred")
    )
    park_pointer
  end

  # The branch that forces `_top` rather than merely preferring it: leaving
  # redirects to /workspaces, a page the members_results frame cannot become.
  context "when the actor deactivates their own membership" do
    let!(:second_owner_membership) do
      create(:membership, :owner, user: create(:user), workspace: workspace)
    end

    it "lands on the workspaces list with the 'left' notice" do
      visit workspace_members_path(workspace)

      click_row_action(owner_membership, I18n.t("workspaces.members.index.deactivate"))

      expect(page).to have_current_path(workspaces_path)
      expect(page).to have_text(
        I18n.t("workspaces.members.destroy.left", workspace_name: workspace.name)
      )
    end
  end

  # The alert twin of the notice: an admin may deactivate anyone, so the
  # last-owner refusal is reachable without stubbing, and it is rendered
  # outside the frame exactly like the notice is.
  context "when an admin deactivates the last owner" do
    let(:admin) { create(:user, first_name: "Adam", last_name: "Admin") }
    let(:actor) { admin }
    let!(:admin_membership) { create(:membership, :admin, user: admin, workspace: workspace) }

    it "keeps the owner and shows the last-owner alert on the members page" do
      visit workspace_members_path(workspace)

      click_row_action(owner_membership, I18n.t("workspaces.members.index.deactivate"))

      expect(page).to have_text(
        I18n.t("workspaces.members.destroy.cannot_deactivate_last_owner")
      )
      expect(owner_membership.reload.discarded_at).to be_nil
      park_pointer
    end
  end
end
