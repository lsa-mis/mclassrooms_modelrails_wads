require "rails_helper"

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): axe AAA coverage for the
# UnitDisplayName admin console — index, new, and edit. Mirrors
# spec/system/admin/bulk_uploads_spec.rb's tenancy setup + sign_in_via_form
# and spec/system/accessibility/workspace_settings_axe_spec.rb's AAA-only
# audit shape (wcag2aaa tag, both themes).
RSpec.describe "Admin unit display names — AAA", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let!(:workspace) { create(:workspace, slug: "unit-display-names-axe-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:unit_display_name) { create(:unit_display_name, workspace: workspace, department_group: "ENGIN", display_name: "College of Engineering") }

  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  it "index is axe-clean at AAA (both themes)" do
    visit admin_unit_display_names_path

    expect(page).to have_selector("h1", text: I18n.t("admin.unit_display_names.index.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on unit display names index: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "new form is axe-clean at AAA (both themes)" do
    visit new_admin_unit_display_name_path

    expect(page).to have_selector("h1", text: I18n.t("admin.unit_display_names.new.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on new unit display name form: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "edit form is axe-clean at AAA (both themes)" do
    visit edit_admin_unit_display_name_path(unit_display_name)

    expect(page).to have_selector("h1", text: I18n.t("admin.unit_display_names.edit.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on edit unit display name form: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
