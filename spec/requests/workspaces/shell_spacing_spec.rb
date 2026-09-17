require "rails_helper"

RSpec.describe "Workspace shell spacing hooks", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme", max_members: 50) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  # The sidebar and the content column open at the same height. The identity
  # bar that used to set this gap is gone (the sidebar switcher carries
  # identity now), so the sidebar is what the content column matches.
  it "opens the sidebar and the content column at the same top gap" do
    get workspace_path(workspace)
    sidebar = Nokogiri::HTML(response.body).at_css("aside[aria-label]")

    expect(sidebar["class"]).to include("pt-4")
  end

  # The section-nav strip sits at px-6; every page's content container must
  # match so headings share one left edge (and don't drift 8px left on
  # mobile). pt-4 keeps the top gap uniform.
  it "uses a consistent px-6 pt-4 content gutter across all shell pages" do
    [
      workspace_path(workspace),
      workspace_members_path(workspace),
      edit_workspace_path(workspace),
      edit_workspace_settings_path(workspace),
      new_workspace_invitation_path(workspace)
    ].each do |path|
      get path
      doc = Nokogiri::HTML(response.body)
      container = doc.at_css("#main-content").css("div").find do |d|
        d["class"]&.include?("pt-4") && d["class"]&.include?("px-6") && d["class"]&.include?("max-w-")
      end
      expect(container).not_to be_nil, "#{path}: no max-width pt-4 content container found"
      expect(container["class"]).to include("px-6"), "#{path}: expected px-6 gutter, got #{container['class']}"
      expect(container["class"]).not_to include("px-4"), "#{path}: px-4 is inconsistent with the identity bar (px-6)"
      expect(container["class"]).not_to include("mx-auto"), "#{path}: content should left-align to the shared edge, not center (mx-auto)"
    end
  end
end
