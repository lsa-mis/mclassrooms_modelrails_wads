# frozen_string_literal: true

require "rails_helper"

# Request spec: verifies the mobile workspace switcher is present in the
# rendered HTML for authenticated users.
#
# The mobile switcher (`mobile: true` variant of _workspace_switcher.html.erb)
# lives inside the hamburger panel in _header.html.erb. Because it carries
# `md:hidden` it is always in the DOM on every authenticated page — we assert
# on the raw response body, not on visibility. We load /workspaces (any
# authenticated page renders the header chrome).
RSpec.describe "Mobile workspace switcher", type: :request do
  let(:user) { create(:user) }
  let!(:second_workspace) do
    ws = create(:workspace)
    create(:membership, :owner, user: user, workspace: ws)
    ws
  end

  before { sign_in(user) }

  describe "user with 2+ workspaces" do
    it "includes mobile switcher links to both workspaces inside the mobile panel" do
      # Reload user so the personal workspace (created by onboarding callback)
      # and the second workspace are both visible to switcher_workspaces.
      user.reload
      personal = user.personal_workspace

      get workspaces_path

      expect(response).to have_http_status(:ok)

      body = response.body

      # Both workspace links should appear in the body (the mobile list is always
      # in the DOM even when visually hidden at md+).
      expect(body).to include(workspace_path(personal))
      expect(body).to include(workspace_path(second_workspace))
    end

    it "caps the mobile switch list at 5 and offers All workspaces for the rest" do
      # personal + second_workspace + 5 more = 7 workspaces; the list shows 5.
      5.times { create(:membership, :owner, user: user, workspace: create(:workspace)) }
      user.reload

      get workspaces_path

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      items = doc.css('#mobile-menu-panel ul[role="list"] > li')
      expect(items.size).to eq(5)
      expect(response.body).to include(I18n.t("navigation.all_workspaces"))
    end
  end

  describe "user with 1 workspace (no switcher)" do
    let(:solo_user) { create(:user) }

    before { sign_in(solo_user) }

    it "omits the switch list but still offers All workspaces (solo user)" do
      solo_user.reload

      get workspaces_path

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      # Nothing to switch → no switch list inside the mobile panel...
      expect(doc.css('#mobile-menu-panel ul[role="list"]')).to be_empty
      # ...but "All workspaces" (the index entry point) still renders in the
      # Workspaces group, not the account menu.
      expect(response.body).to include(workspaces_path)
      expect(response.body).to include(I18n.t("navigation.all_workspaces"))
    end
  end
end
