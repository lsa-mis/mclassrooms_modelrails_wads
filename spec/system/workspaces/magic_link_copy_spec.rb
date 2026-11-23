# frozen_string_literal: true

require "rails_helper"

# The magic-link reveal on the Members page is a `ui :copy` field: no more
# `<code class="break-all">` splitting the token mid-word, and no `role="alert"`
# wrapper that arrives pre-filled and therefore announces nothing. Axe inline (#912).
RSpec.describe "Magic link copy control", type: :system do
  def reveal_magic_link
    user = create(:user)
    workspace = create(:workspace, name: "Acme")
    create(:membership, :owner, user: user, workspace: workspace)
    # Seed-agnostic: CI seeds the global roles, local rspec does not.
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    sign_in_via_form(user)
    visit workspace_members_path(workspace)
    # By id: the members filter bar has its own select labelled "Role".
    select "Member", from: "invitation_role_id"
    click_button I18n.t("workspaces.invitations.index.generate_magic_link")
    expect(page).to have_text(I18n.t("workspaces.invitations.index.magic_link_label"))
  end

  it "renders the reveal as a copy field without the mid-word wrap or the silent alert" do
    reveal_magic_link
    link_noun = I18n.t("workspaces.invitations.index.magic_link_aria")

    within("#magic_link_reveal") do
      expect(page).to have_css("input[readonly][data-copy-target='source'][value*='/invitations/']")
      expect(page).to have_css("button[data-action='copy#copy'][aria-label='#{I18n.t("modelrails_ui.copy.action")} #{link_noun}']")
      expect(page).to have_css("label.sr-only", text: link_noun, visible: :all)
      expect(page).to have_no_css("code.break-all")
    end
    expect(page).to have_no_css("#magic_link_reveal[role='alert']")
    expect(page).to have_css("#magic_link_reveal[data-turbo-temporary]")
  end

  it "copies the URL and announces it" do
    reveal_magic_link
    link_noun = I18n.t("workspaces.invitations.index.magic_link_aria")
    page.execute_script(<<~JS)
      window.__copied = []
      Object.defineProperty(navigator, "clipboard", {
        value: { writeText: (text) => { window.__copied.push(text); return Promise.resolve() } },
        configurable: true
      })
    JS
    url = find("input[data-copy-target='source']").value

    find("button[data-action='copy#copy']").click

    expect(page).to have_css("[data-controller='copy'][data-state='copied']")
    expect(page.evaluate_script("window.__copied")).to eq([ url ])
    expect(find("[data-copy-target='status']", visible: :all).text(:all).strip)
      .to eq(I18n.t("modelrails_ui.copy.copied", label: link_noun))
  end

  it "is axe-clean at AAA in both themes with the reveal open" do
    reveal_magic_link
    axe_options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      axe_violations_in_both_themes(axe_options).join("\n")
  end
end
