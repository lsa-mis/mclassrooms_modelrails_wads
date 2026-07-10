require "rails_helper"

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): axe AAA coverage for the
# CharacteristicDisplayRule admin console — index, new, and edit. Mirrors
# spec/system/admin/bulk_uploads_spec.rb's tenancy setup + sign_in_via_form
# and spec/system/accessibility/workspace_settings_axe_spec.rb's AAA-only
# audit shape (wcag2aaa tag, both themes).
RSpec.describe "Admin characteristic display rules — AAA", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let!(:workspace) { create(:workspace, slug: "characteristic-display-rules-axe-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:rule) { create(:characteristic_display_rule, workspace: workspace, short_code: "whtbrd") }

  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  it "index is axe-clean at AAA (both themes)" do
    visit admin_characteristic_display_rules_path

    expect(page).to have_selector("h1", text: I18n.t("admin.characteristic_display_rules.index.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on characteristic display rules index: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "new form is axe-clean at AAA (both themes)" do
    visit new_admin_characteristic_display_rule_path

    expect(page).to have_selector("h1", text: I18n.t("admin.characteristic_display_rules.new.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on new characteristic display rule form: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "edit form is axe-clean at AAA (both themes)" do
    visit edit_admin_characteristic_display_rule_path(rule)

    expect(page).to have_selector("h1", text: I18n.t("admin.characteristic_display_rules.edit.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on edit characteristic display rule form: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
