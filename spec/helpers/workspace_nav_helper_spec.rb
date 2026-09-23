require "rails_helper"

RSpec.describe WorkspaceNavHelper, type: :helper do
  let(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true,
                        manage_projects: true, manage_settings: true }
    end
  end

  describe "#current_workspace_section" do
    def stub_route(controller_path, action_name)
      allow(helper.controller).to receive(:controller_path).and_return(controller_path)
      allow(helper.controller).to receive(:action_name).and_return(action_name)
    end

    it "is :settings on the workspace Profile edit page" do
      stub_route("workspaces", "edit")
      expect(helper.current_workspace_section).to eq(:settings)
    end

    it "is :settings on the logo picker hub, which the Profile page loads" do
      stub_route("workspaces/logos", "show")
      expect(helper.current_workspace_section).to eq(:settings)
    end

    it "is :settings on members, invitations, and workspace settings controllers (any action)" do
      stub_route("workspaces/members", "index")
      expect(helper.current_workspace_section).to eq(:settings)
      stub_route("workspaces/invitations", "new")
      expect(helper.current_workspace_section).to eq(:settings)
      stub_route("workspaces/settings", "edit")
      expect(helper.current_workspace_section).to eq(:settings)
    end

    it "is nil on the workspace Overview (workspaces#show)" do
      stub_route("workspaces", "show")
      expect(helper.current_workspace_section).to be_nil
    end
  end

  describe "#workspace_shell_nav_items Settings active state" do
    let(:workspace) { create(:workspace, name: "Acme") }
    # The item is derived from the settings sub-nav now, so these examples need
    # a viewer for the policies to answer about (#1153).
    let(:owner) { create(:user) }

    before do
      workspace.memberships.create!(user: owner, role: owner_role)
      allow(Current).to receive(:workspace).and_return(workspace)
      allow(Current).to receive(:user).and_return(owner)
      allow(helper).to receive(:current_page?).and_return(false)
    end

    it "marks Settings active when in the settings section" do
      allow(helper).to receive(:current_workspace_section).and_return(:settings)
      settings = helper.workspace_shell_nav_items.find { |i| i[:label] == I18n.t("workspaces.sidebar.settings") }
      expect(settings[:active]).to be(true)
    end

    it "marks Settings inactive on the Overview" do
      allow(helper).to receive(:current_workspace_section).and_return(nil)
      settings = helper.workspace_shell_nav_items.find { |i| i[:label] == I18n.t("workspaces.sidebar.settings") }
      expect(settings[:active]).to be(false)
    end
  end

  describe "#workspace_shell_nav_items" do
    before { allow(helper).to receive(:current_page?).and_return(false) }

    # The shell item linked to Profile for everyone, and ProfilePolicy gates
    # that page on manage_settings — so a Member saw a Settings link, clicked
    # it, and was refused (#1153). The destination is now the first item of
    # the sub-nav, which is already gated per entry.
    context "the Settings destination follows what the role can actually open" do
      def settings_item_for(permissions)
        role = Role.create!(name: "Probe #{SecureRandom.hex(3)}", slug: "probe-#{SecureRandom.hex(3)}",
                            workspace_id: nil, permissions: permissions)
        workspace = create(:workspace, personal: false)
        member = create(:user)
        workspace.memberships.create!(user: member, role: role)

        allow(Current).to receive(:workspace).and_return(workspace)
        allow(Current).to receive(:user).and_return(member)

        [ workspace, helper.workspace_shell_nav_items.find { |i| i[:label] == I18n.t("workspaces.sidebar.settings") } ]
      end

      it "sends a role that can manage settings to the Profile page" do
        workspace, item = settings_item_for(manage_settings: true, manage_members: true)

        expect(item[:href]).to eq(edit_workspace_path(workspace))
      end

      it "sends a Member, who cannot open Profile, to the members list instead" do
        workspace, item = settings_item_for(manage_projects: true)

        expect(item[:href]).to eq(workspace_members_path(workspace)),
          "a Member's only route into settings was a link to a page they are refused"
      end

      # The issue expected Settings to disappear for a Viewer. It does not, and
      # should not: MembershipPolicy#index? is `membership.present?`, so any
      # member — Viewer included — may open the members list. The item is
      # dropped only when the sub-nav is genuinely empty, which no membership
      # produces today; the guard is there so a fork that tightens that policy
      # does not reintroduce a link to nothing.
      it "still offers a permission-less role the members list" do
        workspace, item = settings_item_for({})

        expect(item).not_to be_nil
        expect(item[:href]).to eq(workspace_members_path(workspace))
      end
    end

    # Personal workspaces used to omit Settings and offer a bespoke "Customize"
    # modal holding the same two fields the Profile page already served. One
    # workspace, one shape — both kinds now get the same three items.
    it "gives a personal workspace the same items as an org" do
      viewer = create(:user)
      personal = create(:workspace, personal: true)
      org = create(:workspace, personal: false)
      [ personal, org ].each { |w| w.memberships.create!(user: viewer, role: owner_role) }
      allow(Current).to receive(:user).and_return(viewer)

      allow(Current).to receive(:workspace).and_return(personal)
      personal_labels = helper.workspace_shell_nav_items.map { |i| i[:label] }
      allow(Current).to receive(:workspace).and_return(org)
      org_labels = helper.workspace_shell_nav_items.map { |i| i[:label] }

      expect(personal_labels).to eq(org_labels)
      expect(personal_labels).to include(I18n.t("workspaces.sidebar.settings"))
    end

    it "includes Settings (active: false) for an org workspace (2 items)" do
      ws = create(:workspace, personal: false)
      viewer = create(:user)
      ws.memberships.create!(user: viewer, role: owner_role)
      allow(Current).to receive(:workspace).and_return(ws)
      allow(Current).to receive(:user).and_return(viewer)
      items = helper.workspace_shell_nav_items
      expect(items.map { |i| i[:label] }).to include(I18n.t("workspaces.sidebar.settings"))
      expect(items.last[:active]).to be(false)
    end
  end
end
