require "rails_helper"

# #983. UI::Select pins its HEIGHT to the 44px AAA floor
# (`min-h-[var(--form-input-height)]`) and its width to nothing. In the members
# table the select sits in a `flex-1` (basis zero) beside a submit button inside
# a table cell, so its width is whatever is left over — 47px on a desktop
# viewport locally, three pixels of margin, and 43px on CI, where the teardown
# audit caught it as mc-target-size-44.
#
# Measured at PHONE width, where the leftover space is smallest and the failure
# is deterministic rather than a coin flip on column widths.
RSpec.describe "Inline role select target size", type: :system do
  let(:workspace) { create(:workspace) }
  let(:owner) { create(:user) }
  let!(:owner_membership) { create(:membership, :owner, user: owner, workspace: workspace) }

  before { %w[admin member viewer].each { |slug| Role.system_default!(slug) } }

  it "keeps the select at or above the 44px floor on both axes" do
    sign_in_via_form(owner)

    with_viewport(ResponsiveViewport::PHONE) do
      visit workspace_members_path(workspace)

      within "##{ActionView::RecordIdentifier.dom_id(owner_membership)}" do
        click_link I18n.t("workspaces.members.index.edit_role")
        expect(page).to have_css("#membership_role_id")
      end

      box = page.evaluate_script(<<~JS)
        (() => {
          const r = document.getElementById("membership_role_id").getBoundingClientRect();
          return { w: Math.round(r.width), h: Math.round(r.height) };
        })()
      JS

      # Reported as one message so a failure names both axes and the actual box.
      expect([ box["w"], box["h"] ].min).to be >= 44,
        "role select rendered #{box['w']}x#{box['h']} — WCAG 2.5.5 (AAA) floor is 44x44"
    end
  end
end
