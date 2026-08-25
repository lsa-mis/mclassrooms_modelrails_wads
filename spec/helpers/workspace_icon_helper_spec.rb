require "rails_helper"

RSpec.describe WorkspaceIconHelper, type: :helper do
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
      workspace.update_columns(primary_color: 270)
      workspace.logo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "logo.png",
        content_type: "image/png"
      )
      workspace.update_columns(logo_source: "upload")

      result = helper.workspace_icon_for(workspace, size: :md)

      expect(result).to have_css("[data-controller='avatar'] img.w-10.h-10[data-avatar-target='image'][aria-hidden='true']")
      # The action wiring is what makes the pair recoverable; a target without it
      # never swaps. The standby span must be hidden (visible: :all would pass with
      # both nodes exposed) and must carry the workspace's custom hue so the
      # recovered initials keep the brand color.
      expect(result).to have_css("[data-controller='avatar'] img[data-action='error->avatar#showFallback']")
      expect(result).to have_css(
        "[data-controller='avatar'] span[data-avatar-target='fallback'][style='--hue: 270']",
        visible: :hidden
      )
    end

    # #755: default-hue workspaces take the component's bg-interactive branch,
    # same as default-hue user avatars — the two sibling helpers agree.
    it "recovers a default-hue logo to bg-interactive initials (no fixed hue)" do
      workspace = create(:workspace, name: "Acme Co")
      workspace.identity
      workspace.logo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "logo.png",
        content_type: "image/png"
      )
      workspace.update_columns(logo_source: "upload")

      result = helper.workspace_icon_for(workspace, size: :md)

      expect(result).to have_css(
        "[data-controller='avatar'] span[data-avatar-target='fallback'].bg-interactive",
        visible: :hidden
      )
      expect(result).to have_no_css("span[style]", visible: :all)
    end

    it "renders hue-tinted initials when the workspace has a custom color" do
      workspace = create(:workspace, name: "Acme Co")
      workspace.update_columns(primary_color: 270)

      result = helper.workspace_icon_for(workspace, size: :sm)

      expect(result).to have_css("span.w-8.h-8.bg-hue-initials[aria-hidden='true']", text: workspace.identity.initials)
      expect(result).to have_css("span[style='--hue: 270']")
    end

    it "renders bg-interactive initials at the default color (#755 parity with avatar_helper)" do
      workspace = create(:workspace, name: "Acme Co")

      result = helper.workspace_icon_for(workspace, size: :sm)

      expect(result).to have_css("span.w-8.h-8.bg-interactive[aria-hidden='true']", text: workspace.identity.initials)
      expect(result).to have_no_css("span.bg-hue-initials")
      expect(result).to have_no_css("span[style]")
    end

    it "renders :lg initials at the component's text-lg (licensed delta from the old text-xl)" do
      workspace = create(:workspace, name: "Acme Co")

      result = helper.workspace_icon_for(workspace, size: :lg)

      expect(result).to have_css("span.w-16.h-16.text-lg", text: workspace.identity.initials)
      expect(result).to have_no_css("span.text-xl")
    end
  end
end
