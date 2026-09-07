# frozen_string_literal: true

require "rails_helper"

# The magic-link reveal on the Members page is a `ui :copy` field: no more
# `<code class="break-all">` splitting the token mid-word, and no `role="alert"`
# wrapper that arrives pre-filled and therefore announces nothing. Axe inline (#912).
RSpec.describe "Magic link copy control", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:link_noun) { I18n.t("workspaces.invitations.index.magic_link_aria") }

  before do
    # Seed-agnostic: CI seeds the global roles, local rspec does not.
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    sign_in_via_form(user)
    visit workspace_members_path(workspace)
    # Scoped by id, not the "Role" label: the members-index filter bar above
    # this form has its own select labelled "Role" (workspaces.members.index.role),
    # so `from: I18n.t("...magic_link_role_label")` is ambiguous on this page.
    select "Member", from: "invitation_role_id"
    click_button I18n.t("workspaces.invitations.index.generate_magic_link")
    expect(page).to have_text(I18n.t("workspaces.invitations.index.magic_link_label"))
  end

  it "renders the reveal as a copy field without the mid-word wrap or the silent alert" do
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
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      axe_violations_in_both_themes(axe_options).join("\n")
  end
end
