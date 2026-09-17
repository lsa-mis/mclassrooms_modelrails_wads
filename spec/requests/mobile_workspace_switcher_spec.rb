# frozen_string_literal: true

require "rails_helper"

# Request spec: the phone's workspace switcher in the rendered HTML.
#
# It renders above the section tabs on WORKSPACE pages (#1077), a second copy
# of the sidebar switcher carrying a `-mobile` id suffix — the sidebar copy is
# display:none below md, not absent. It replaced the inline list that lived in
# the hamburger, so the workspaces index no longer carries a switcher at all
# (the index IS the switcher; see workspace_switcher_spec for that placement).
# Everything here asserts on the raw body: the mobile copy is md:hidden, so it
# is in the DOM at every width.
RSpec.describe "Mobile workspace switcher", type: :request do
  let(:user) { create(:user) }
  let!(:second_workspace) do
    ws = create(:workspace)
    create(:membership, :owner, user: user, workspace: ws)
    ws
  end

  before { sign_in(user) }

  def mobile_menu_items(html)
    Nokogiri::HTML(html).css("#workspace-switcher-menu-mobile a[role=menuitem]")
  end

  describe "user with 2+ workspaces" do
    it "links both workspaces from the mobile dropdown on a workspace page" do
      user.reload
      personal = user.personal_workspace

      get workspace_path(personal)

      expect(response).to have_http_status(:ok)
      hrefs = mobile_menu_items(response.body).map { |a| a["href"] }
      expect(hrefs).to include(workspace_path(personal), workspace_path(second_workspace))
    end

    # The hamburger's old list was capped so the panel stayed a bounded height;
    # the dropdown keeps that bound so a long list cannot run off a 375px
    # screen. Current workspace pinned first, then five total, then the index
    # link as the overflow.
    it "caps the mobile dropdown at five workspaces and offers All workspaces for the rest" do
      5.times { create(:membership, :owner, user: user, workspace: create(:workspace)) }
      user.reload
      personal = user.personal_workspace

      get workspace_path(personal)

      items = mobile_menu_items(response.body)
      workspace_items = items.reject { |a| a["href"] == workspaces_path }
      expect(workspace_items.size).to eq(5)
      expect(workspace_items.first["href"]).to eq(workspace_path(personal))
      expect(items.map { |a| a["href"] }).to include(workspaces_path)
    end

    it "does not cap the desktop sidebar copy" do
      5.times { create(:membership, :owner, user: user, workspace: create(:workspace)) }
      user.reload

      get workspace_path(user.personal_workspace)

      desktop_items = Nokogiri::HTML(response.body)
        .css("#workspace-switcher-menu a[role=menuitem]")
        .reject { |a| a["href"] == workspaces_path }
      expect(desktop_items.size).to eq(7)
    end
  end

  describe "user with 1 workspace" do
    let(:solo_user) { create(:user) }

    before { sign_in(solo_user) }

    it "still renders the trigger (it is the only thing naming the workspace on a phone) with only the index link in its menu" do
      solo_user.reload

      get workspace_path(solo_user.personal_workspace)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("#workspace-switcher-button-mobile")).not_to be_nil
      expect(mobile_menu_items(response.body).map { |a| a["href"] }).to eq([ workspaces_path ])
    end
  end

  describe "the hamburger" do
    it "no longer lists workspaces, but still offers All workspaces from the account group" do
      get workspace_path(user.reload.personal_workspace)

      panel = Nokogiri::HTML(response.body).at_css("#mobile-menu-panel")
      expect(panel.css("a[href^='/workspaces/']")).to be_empty, "the hamburger still links individual workspaces"
      expect(panel.css("a[href='#{workspaces_path}']")).not_to be_empty, "the hamburger lost its All workspaces link"
    end
  end
end
