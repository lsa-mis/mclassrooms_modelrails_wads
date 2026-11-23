# frozen_string_literal: true

require "rails_helper"

# Row actions post from inside the members_results frame and answer with a redirect's flash, which must
# reach the page (#1050, like #1038). Leaving redirects to another page, so Deactivate can't be a row stream.
RSpec.describe "Member row actions escape the members frame", type: :system do
  def add_owner_and_member
    owner = create(:user, first_name: "Olivia", last_name: "Owner")
    workspace = create(:workspace, name: "Acme", max_members: 50)
    owner_membership = create(:membership, :owner, user: owner, workspace: workspace)
    member = create(:user, first_name: "Mel", last_name: "Member")
    [ owner_membership, create(:membership, user: member, workspace: workspace) ]
  end

  def sign_in_and_visit_members(actor_membership)
    sign_in_via_form(actor_membership.user)
    visit workspace_members_path(actor_membership.workspace)
  end

  def row_for(membership)
    "##{ActionView::RecordIdentifier.dom_id(membership)}"
  end

  def click_row_action(membership, label)
    within(row_for(membership)) { click_button label }
  end

  def confirm_deactivate(membership, action: I18n.t("workspaces.members.deactivate_dialog.action"))
    click_row_action(membership, I18n.t("workspaces.members.index.deactivate"))
    within("dialog[open]") { click_button action }
  end

  it "says what Deactivate removes, and Cancel leaves the member active" do
    owner_membership, member_membership = add_owner_and_member
    sign_in_and_visit_members(owner_membership)

    click_row_action(member_membership, I18n.t("workspaces.members.index.deactivate"))

    expect(page).to have_css("dialog[open]", text: I18n.t("workspaces.members.deactivate_dialog.message",
                                                           name: member_membership.user.full_name,
                                                           workspace_name: member_membership.workspace.name))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations with the Deactivate dialog open: #{axe_violations_in_both_themes(axe_options).join("\n")}"

    within("dialog[open]") { click_button I18n.t("modals.cancel") }

    expect(page).to have_no_css("dialog[open]")
    expect(page).to have_css(row_for(member_membership), text: I18n.t("workspaces.members.index.active"))
    expect(member_membership.reload).not_to be_discarded
  end

  it "shows the deactivated notice after Deactivate, on an accessible restored page" do
    owner_membership, member_membership = add_owner_and_member
    sign_in_and_visit_members(owner_membership)

    confirm_deactivate(member_membership)

    expect(page).to have_text(I18n.t("workspaces.members.destroy.deactivated"))
    expect(page).to have_css(row_for(member_membership),
                             text: I18n.t("workspaces.members.index.deactivated"))

    # #912: audits the full-page render this fix creates; the transient toast,
    # asserted above, is removed so the audit reads the settled page.
    page.execute_script(
      "document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())"
    )
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on the restored members page: " \
      "#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "shows the reactivated notice after Reactivate" do
    owner_membership, member_membership = add_owner_and_member
    member_membership.update!(discarded_at: Time.current)
    sign_in_and_visit_members(owner_membership)

    click_row_action(member_membership, I18n.t("workspaces.members.index.reactivate"))

    expect(page).to have_text(
      I18n.t("workspaces.members.reactivations.create.reactivated")
    )
  end

  it "shows the transferred notice after Transfer ownership" do
    owner_membership, member_membership = add_owner_and_member
    sign_in_and_visit_members(owner_membership)

    click_row_action(member_membership, I18n.t("workspaces.members.index.transfer_ownership"))

    expect(page).to have_text(
      I18n.t("workspaces.members.ownership_transfers.create.transferred")
    )
  end

  # The branch that forces `_top` rather than merely preferring it: leaving
  # redirects to /workspaces, a page the members_results frame cannot become.
  context "when the actor deactivates their own membership" do
    def add_second_owner(workspace)
      create(:membership, :owner, user: create(:user), workspace: workspace)
    end

    it "lands on the workspaces list with the 'left' notice" do
      owner_membership, _member_membership = add_owner_and_member
      add_second_owner(owner_membership.workspace)
      sign_in_and_visit_members(owner_membership)

      confirm_deactivate(owner_membership, action: I18n.t("workspaces.members.deactivate_dialog.leave_action"))

      expect(page).to have_current_path(workspaces_path)
      expect(page).to have_text(
        I18n.t("workspaces.members.destroy.left", workspace_name: owner_membership.workspace.name)
      )
    end
  end

  # The alert twin of the notice: an admin may deactivate anyone, so the
  # last-owner refusal is reachable without stubbing.
  context "when an admin deactivates the last owner" do
    it "keeps the owner and shows the last-owner alert on the members page" do
      owner_membership, _member_membership = add_owner_and_member
      admin = create(:user, first_name: "Adam", last_name: "Admin")
      admin_membership = create(:membership, :admin, user: admin, workspace: owner_membership.workspace)
      sign_in_and_visit_members(admin_membership)

      confirm_deactivate(owner_membership)

      expect(page).to have_text(
        I18n.t("workspaces.members.destroy.cannot_deactivate_last_owner")
      )
      expect(owner_membership.reload.discarded_at).to be_nil
    end
  end
end
