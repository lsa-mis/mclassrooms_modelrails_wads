require "rails_helper"

RSpec.describe SettingsNavigationHelper, type: :helper do
  describe "#settings_context_kind" do
    it "returns :personal when Current.workspace.personal? is true" do
      personal = build_stubbed(:workspace, personal: true)
      allow(Current).to receive(:workspace).and_return(personal)
      expect(helper.settings_context_kind).to eq(:personal)
    end

    it "returns :org when Current.workspace.personal? is false" do
      org = build_stubbed(:workspace, personal: false)
      allow(Current).to receive(:workspace).and_return(org)
      expect(helper.settings_context_kind).to eq(:org)
    end

    it "returns :personal when Current.workspace is nil (safe default for unauthenticated edge)" do
      allow(Current).to receive(:workspace).and_return(nil)
      expect(helper.settings_context_kind).to eq(:personal)
    end
  end

  describe "#render_nav_item_if_permitted" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }

    before do
      allow(Current).to receive(:user).and_return(user)
      allow(Current).to receive(:workspace).and_return(workspace)
    end

    it "yields when the policy permits the action" do
      allow(WorkspacePolicy).to receive(:new)
        .with(user, workspace).and_return(instance_double(WorkspacePolicy, edit?: true))

      output = helper.render_nav_item_if_permitted(workspace, action: :edit?) { "RENDERED" }
      expect(output).to eq("RENDERED")
    end

    it "returns nil when the policy denies the action" do
      allow(WorkspacePolicy).to receive(:new)
        .with(user, workspace).and_return(instance_double(WorkspacePolicy, edit?: false))

      output = helper.render_nav_item_if_permitted(workspace, action: :edit?) { "RENDERED" }
      expect(output).to be_nil
    end

    it "infers the policy class from the record" do
      membership = create(:membership, user: user, workspace: workspace)
      allow(MembershipPolicy).to receive(:new)
        .with(user, membership).and_return(instance_double(MembershipPolicy, index?: true))

      output = helper.render_nav_item_if_permitted(membership, action: :index?) { "RENDERED" }
      expect(output).to eq("RENDERED")
    end

    context "with an explicit policy_class:" do
      it "yields when the given policy class permits the action" do
        allow(Workspaces::SettingsPolicy).to receive(:new)
          .with(user, workspace).and_return(instance_double(Workspaces::SettingsPolicy, update?: true))

        output = helper.render_nav_item_if_permitted(
          workspace, action: :update?, policy_class: Workspaces::SettingsPolicy
        ) { "RENDERED" }
        expect(output).to eq("RENDERED")
      end

      # Discriminator: the record's inferred policy (WorkspacePolicy) would
      # permit, but the explicitly-requested SettingsPolicy denies — so a nil
      # result proves the helper consults the given class, not the inferred one.
      it "consults the given policy class instead of inferring from the record" do
        allow(WorkspacePolicy).to receive(:new)
          .and_return(instance_double(WorkspacePolicy, update?: true))
        allow(Workspaces::SettingsPolicy).to receive(:new)
          .with(user, workspace).and_return(instance_double(Workspaces::SettingsPolicy, update?: false))

        output = helper.render_nav_item_if_permitted(
          workspace, action: :update?, policy_class: Workspaces::SettingsPolicy
        ) { "RENDERED" }
        expect(output).to be_nil
      end
    end
  end

  describe "#current_workspace_announcement_for_aria_live" do
    let(:user) { create(:user) }

    before do
      allow(Current).to receive(:user).and_return(user)
    end

    it "returns nil when Current.workspace is nil" do
      allow(Current).to receive(:workspace).and_return(nil)
      expect(helper.current_workspace_announcement_for_aria_live).to be_nil
    end

    it "returns nil when Current.workspace.personal? is true" do
      personal = build_stubbed(:workspace, personal: true)
      allow(Current).to receive(:workspace).and_return(personal)
      expect(helper.current_workspace_announcement_for_aria_live).to be_nil
    end

    it "returns the full item list with workspace name and role for an Owner" do
      workspace = create(:workspace, name: "Acme Corp", personal: false)
      create(:membership, :owner, user: user, workspace: workspace)
      allow(Current).to receive(:workspace).and_return(workspace)

      result = helper.current_workspace_announcement_for_aria_live
      expect(result).to include("Acme Corp")
      expect(result).to include("Owner")
      expect(result).to include("Profile")
      expect(result).to include("Members")
      expect(result).to include("Invitations")
      expect(result).to include("Limits & Plan")
    end

    it "includes Profile (manage_settings-gated) for an Admin alongside Members, Invitations, and Limits & Plan" do
      # Post route-consolidation, Profile is gated by Workspaces::ProfilePolicy
      # which checks manage_settings (held by Admin). Admins formerly edited
      # workspace identity via the branding route; ProfilePolicy preserves that
      # capability surface intentionally — see ProfilePolicy class comment.
      workspace = create(:workspace, name: "Beta LLC", personal: false)
      create(:membership, :admin, user: user, workspace: workspace)
      allow(Current).to receive(:workspace).and_return(workspace)

      result = helper.current_workspace_announcement_for_aria_live
      expect(result).to include("Beta LLC")
      expect(result).to include("Admin")
      expect(result).to include("Profile")
      expect(result).to include("Members")
      expect(result).to include("Invitations")
      expect(result).to include("Limits & Plan")
    end

    it "falls back to the Member role label when no membership is found (defensive edge)" do
      workspace = create(:workspace, name: "Ghost Inc", personal: false)
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
      allow(Current).to receive(:workspace).and_return(workspace)

      result = helper.current_workspace_announcement_for_aria_live
      expect(result).to include("Ghost Inc")
      expect(result).to include("Member")
    end
  end
end
