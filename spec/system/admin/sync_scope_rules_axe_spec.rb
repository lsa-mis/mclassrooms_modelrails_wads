require "rails_helper"

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): axe AAA coverage for the
# SyncScopeRule admin console — index (including the standing
# next-sync-run warning banner), new, and edit. Mirrors
# spec/system/admin/bulk_uploads_spec.rb's tenancy setup + sign_in_via_form
# and spec/system/accessibility/workspace_settings_axe_spec.rb's AAA-only
# audit shape (wcag2aaa tag, both themes).
RSpec.describe "Admin sync scope rules — AAA", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let!(:workspace) { create(:workspace, slug: "sync-scope-rules-axe-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:sync_scope_rule) { create(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "ANN_ARBOR") }

  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  it "index (with the sync-effective warning banner) is axe-clean at AAA (both themes)" do
    visit admin_sync_scope_rules_path

    expect(page).to have_selector("h1", text: I18n.t("admin.sync_scope_rules.index.title"))
    expect(page).to have_content(I18n.t("admin.sync_scope_rules.index.sync_effective_notice"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on sync scope rules index: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "new form is axe-clean at AAA (both themes)" do
    visit new_admin_sync_scope_rule_path

    expect(page).to have_selector("h1", text: I18n.t("admin.sync_scope_rules.new.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on new sync scope rule form: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "edit form is axe-clean at AAA (both themes)" do
    visit edit_admin_sync_scope_rule_path(sync_scope_rule)

    expect(page).to have_selector("h1", text: I18n.t("admin.sync_scope_rules.edit.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on edit sync scope rule form: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
