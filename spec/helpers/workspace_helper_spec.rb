require "rails_helper"

RSpec.describe WorkspaceHelper, type: :helper do
  describe "#workspace_icon_for" do
    it "renders the owner-avatar fallback at the requested size" do
      user = create(:user)
      user.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      user.update_columns(avatar_source: "upload")

      result = helper.workspace_icon_for(user.personal_workspace, size: :sm)

      expect(result).to have_css("img.w-8.h-8")
    end

    it "renders an uploaded logo with broken-image recovery wiring (component path)" do
      workspace = create(:workspace, name: "Acme Co")
      workspace.identity  # ensure identity exists per the model's accessor
      workspace.logo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "logo.png",
        content_type: "image/png"
      )

      result = helper.workspace_icon_for(workspace, size: :md)

      expect(result).to have_css("[data-controller='avatar'] img.w-10.h-10[data-avatar-target='image'][aria-hidden='true']")
      # The action wiring is what makes the pair recoverable; a target without it
      # never swaps. The standby span must be hidden (visible: :all would pass with
      # both nodes exposed) and must carry the workspace's hue so the recovered
      # initials keep the brand color.
      expect(result).to have_css("[data-controller='avatar'] img[data-action='error->avatar#showFallback']")
      expect(result).to have_css(
        "[data-controller='avatar'] span[data-avatar-target='fallback'][style='--hue: #{workspace.identity.hue}']",
        visible: :hidden
      )
    end

    it "renders hue-tinted initials through the component when no image exists" do
      workspace = create(:workspace, name: "Acme Co")

      result = helper.workspace_icon_for(workspace, size: :sm)

      expect(result).to have_css("span.w-8.h-8.bg-hue-initials[aria-hidden='true']", text: workspace.identity.initials)
      expect(result).to have_css("span[style='--hue: #{workspace.identity.hue}']")
    end

    it "renders :lg initials at the component's text-lg (licensed delta from the old text-xl)" do
      workspace = create(:workspace, name: "Acme Co")

      result = helper.workspace_icon_for(workspace, size: :lg)

      expect(result).to have_css("span.w-16.h-16.text-lg", text: workspace.identity.initials)
      expect(result).to have_no_css("span.text-xl")
    end
  end

  describe "#switcher_current_workspace" do
    # first_name pinned so the personal workspace ("Zed's Workspace") sorts
    # after the org workspaces in the alphabetical cold-start test below.
    let(:user) { create(:user, first_name: "Zed") }

    before do
      allow(Current).to receive(:user).and_return(user)
      allow(Current).to receive(:workspace).and_return(nil)
    end

    it "falls back to the most-recently-accessed workspace when neither an active workspace nor session memory exists" do
      recent = create(:workspace, name: "Recent Org")
      stale = create(:workspace, name: "Stale Org")
      create(:membership, :owner, user: user, workspace: recent, last_accessed_at: 1.minute.ago)
      create(:membership, :owner, user: user, workspace: stale, last_accessed_at: 1.week.ago)

      expect(helper.switcher_current_workspace).to eq(recent)
    end

    it "falls back to the alphabetically-first workspace when no membership has been accessed yet" do
      zeta = create(:workspace, name: "Zeta Org")
      acme = create(:workspace, name: "Acme Org")
      create(:membership, :owner, user: user, workspace: zeta)
      create(:membership, :owner, user: user, workspace: acme)
      user.memberships.update_all(last_accessed_at: nil)

      expect(helper.switcher_current_workspace).to eq(acme)
    end

    it "prefers the session-remembered workspace over recency" do
      remembered = create(:workspace, name: "Remembered Org")
      recent = create(:workspace, name: "Recent Org")
      create(:membership, :owner, user: user, workspace: remembered, last_accessed_at: 1.week.ago)
      create(:membership, :owner, user: user, workspace: recent, last_accessed_at: 1.minute.ago)
      session[:current_workspace_id] = remembered.id

      expect(helper.switcher_current_workspace).to eq(remembered)
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
