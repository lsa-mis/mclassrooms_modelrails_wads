require "rails_helper"

# Defense-in-depth against the cross-workspace authorization footgun.
#
# Tenant isolation in this template is compositional, not ambient: `Tenanted`
# installs NO `default_scope` (see app/docs/developer/extending.md), so a record
# is kept in-workspace only because controllers resolve it through the
# request's own workspace (`@workspace.memberships...`). If a controller ever
# loads a Tenanted record unscoped (`Membership.find(params[:id])`), the record
# can belong to a workspace the user is not a member of — yet
# `ApplicationPolicy#can?` keys its permission check off `Current.workspace`, so
# a user with a privileged role in THEIR workspace would be authorized to act on
# a FOREIGN record.
#
# This spec pins the guard that closes that gap
# (ApplicationPolicy#record_in_current_workspace?): permission checks that flow
# through workspace membership must fail closed when the record does not belong
# to `Current.workspace`. Exercised through MembershipPolicy, whose actions gate
# on `can?("manage_members")` / `can?("manage_workspace")` — the same
# membership-derived path ProjectPolicy used upstream (Projects is removed in
# this fork; Membership is a Tenanted record with the identical guard).
RSpec.describe "Cross-workspace authorization guard" do
  let(:home_workspace) { create(:workspace) }
  let(:foreign_workspace) { create(:workspace) }
  let(:user) { create(:user) }

  # The user is a full OWNER of their home workspace — they hold every
  # workspace-level permission (manage_workspace, manage_members, ...) THERE.
  before do
    Current.workspace = home_workspace
    create(:membership, :owner, user: user, workspace: home_workspace)
  end

  context "when a Tenanted record belongs to a different workspace" do
    # A membership in a workspace the user is not a member of. Simulates the
    # footgun: it was loaded unscoped and handed to a policy while
    # Current.workspace is still the user's home workspace.
    let(:foreign_membership) do
      create(:membership, workspace: foreign_workspace, user: create(:user))
    end

    it "denies a manage_members-gated action on the foreign record" do
      # update? => can?("manage_members"). Without the guard, can?("manage_members")
      # consults the user's HOME membership (owner) and returns true — authorizing
      # edits to a membership in a workspace the user has no membership in.
      expect(MembershipPolicy.new(user, foreign_membership).update?).to be false
    end

    it "denies a manage_workspace-gated action on the foreign record" do
      expect(MembershipPolicy.new(user, foreign_membership).transfer_ownership?).to be false
    end
  end

  context "when the Tenanted record belongs to Current.workspace" do
    # Regression guard: the fix must NOT break legitimate same-workspace
    # authorization. Another member's membership in the user's home workspace.
    let(:home_membership) do
      create(:membership, workspace: home_workspace, user: create(:user))
    end

    it "still allows a manage_members-gated action" do
      expect(MembershipPolicy.new(user, home_membership).update?).to be true
    end
  end
end
