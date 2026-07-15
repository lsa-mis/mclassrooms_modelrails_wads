require "rails_helper"

# Defense-in-depth against the cross-workspace authorization footgun.
#
# Tenant isolation in this template is compositional, not ambient: `Tenanted`
# installs NO `default_scope` (see app/docs/developer/extending.md), so a record
# is kept in-workspace only because controllers resolve it through the
# request's own workspace (`@workspace.projects...`). If a controller ever loads
# a Tenanted record unscoped (`Project.find(params[:id])`), the record can
# belong to a workspace the user is not a member of — yet `ApplicationPolicy#can?`
# keys its permission check off `Current.workspace`, so a user with a privileged
# role in THEIR workspace would be authorized to act on a FOREIGN record.
#
# This spec pins the guard that closes that gap: permission checks that flow
# through workspace membership must fail closed when the record does not belong
# to `Current.workspace`.
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
    # A project the user has NO relationship to, in a workspace they are not a
    # member of. Simulates the footgun: it was loaded unscoped and handed to a
    # policy while Current.workspace is still the user's home workspace.
    let(:foreign_project) do
      create(:project, workspace: foreign_workspace, created_by: create(:user))
    end

    it "denies a manage_workspace-gated action on the foreign record" do
      # archive? => project_membership&.creator? || can?("manage_workspace").
      # Without the guard, can?("manage_workspace") consults the user's HOME
      # membership (owner) and returns true — authorizing archival of a project
      # in a workspace the user has no membership in.
      expect(ProjectPolicy.new(user, foreign_project).archive?).to be false
    end

    it "denies destroy on the foreign record" do
      expect(ProjectPolicy.new(user, foreign_project).destroy?).to be false
    end
  end

  context "when the Tenanted record belongs to Current.workspace" do
    # Regression guard: the fix must NOT break legitimate same-workspace
    # authorization. The user owns a project in their home workspace.
    let(:home_project) do
      create(:project, workspace: home_workspace, created_by: user)
    end

    before { create(:project_membership, :creator, project: home_project, user: user) }

    it "still allows a manage_workspace-gated action" do
      expect(ProjectPolicy.new(user, home_project).archive?).to be true
    end
  end
end
