require "rails_helper"

RSpec.describe "Workspace pages wear the brand", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in_via_form(user) }

  def interactive_background
    page.evaluate_script(<<~JS)
      (() => {
        const probe = document.createElement("div");
        probe.style.backgroundColor = "var(--color-interactive)";
        document.body.append(probe);
        const brand = getComputedStyle(probe).backgroundColor;
        probe.remove();
        return brand;
      })()
    JS
  end

  def save_identity_background
    button = find_button(I18n.t("workspaces.settings.edit.sections.identity_submit"))
    page.evaluate_script("getComputedStyle(arguments[0]).backgroundColor", button)
  end

  it "paints a default-hue workspace's buttons in the brand's interactive color" do
    visit edit_workspace_path(workspace)

    expect(save_identity_background).to eq(interactive_background)
    expect(save_identity_background).to include("251.6")
  end

  it "paints a custom-hue workspace's buttons in its own hue" do
    workspace.update!(primary_color: 145)
    visit edit_workspace_path(workspace)

    expect(save_identity_background).to include("145")
  end
end
