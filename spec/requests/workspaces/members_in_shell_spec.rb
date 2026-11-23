require "rails_helper"

RSpec.describe "Members & Invitations in the workspace shell", type: :request do
  def signed_in_owner
    user = create(:user)
    owner = create(:membership, :owner, user: user, workspace: create(:workspace, name: "Acme", max_members: 50))
    sign_in(owner.user)
    owner
  end

  it "renders the Members index in the shell with Settings primary-active and Members sub-active" do
    get workspace_members_path(signed_in_owner.workspace)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#settings-aria-live")).to be_nil # not the settings hub
    subnav = doc.at_css('nav[aria-label="' + I18n.t("settings.sidebar.strip_heading.workspace") + '"]')
    members_current = subnav.css('a[aria-current="page"]').find { |a| a.text.include?(I18n.t("settings.sidebar.items.members")) }
    expect(members_current).not_to be_nil
  end

  it "renders the invite screen in the shell with Settings still primary-active" do
    get new_workspace_invitation_path(signed_in_owner.workspace)
    doc = Nokogiri::HTML(response.body)
    settings_link = doc.css('a[aria-current="page"]').find { |a| a.text.include?(I18n.t("workspaces.sidebar.settings")) }
    expect(settings_link).not_to be_nil
    expect(doc.at_css("#settings-aria-live")).to be_nil
  end
end
