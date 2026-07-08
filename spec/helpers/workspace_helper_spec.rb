require "rails_helper"

RSpec.describe WorkspaceHelper, type: :helper do
  describe "#current_workspace_section" do
    def stub_route(controller_path, action_name)
      allow(helper.controller).to receive(:controller_path).and_return(controller_path)
      allow(helper.controller).to receive(:action_name).and_return(action_name)
    end

    it "is :settings on the workspace Profile edit page" do
      stub_route("workspaces", "edit")
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

    before do
      allow(Current).to receive(:workspace).and_return(workspace)
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

    it "omits Settings for a personal workspace (1 item)" do
      ws = create(:workspace, personal: true)
      allow(Current).to receive(:workspace).and_return(ws)
      labels = helper.workspace_shell_nav_items.map { |i| i[:label] }
      expect(labels).to eq([ I18n.t("workspaces.sidebar.overview") ])
    end

    it "includes Settings (active: false) for an org workspace (3 items)" do
      ws = create(:workspace, personal: false)
      allow(Current).to receive(:workspace).and_return(ws)
      items = helper.workspace_shell_nav_items
      expect(items.map { |i| i[:label] }).to include(I18n.t("workspaces.sidebar.settings"))
      expect(items.last[:active]).to be(false)
    end
  end
end
