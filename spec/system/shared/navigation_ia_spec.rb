require "rails_helper"

# Task 10 (Navigation IA): under MiClassrooms' :shared tenancy posture the
# signed-in shell must read as a single-tenant directory app — no workspace
# switcher, no "All workspaces" link (the switcher's "see all" companion —
# see shared/_user_menu), and no workspace-creation affordance anywhere in
# the header/nav chrome. An admin-only "Admin" nav region (a labeled
# disclosure, populated by the product-navigation phase with the admin
# section links) is gated by RoleResolver via the current_grant helper
# (app/helpers/application_helper.rb).
#
# Stubs Rails.configuration.x.tenancy the same way spec/requests/test_login_spec.rb
# and spec/requests/omniauth_okta_spec.rb do, rather than relying on process
# ENV (WORKSPACE_ON_SIGNUP isn't loaded into the test process — no dotenv gem
# wired into app boot; only .env.example documents it).
#
# The template's own specs (spec/system/user_menu_spec.rb,
# spec/requests/mobile_workspace_switcher_spec.rb) already pin the opposite
# direction — the switcher and "All workspaces" still render under the
# default :personal posture — so that side isn't re-asserted here.
RSpec.describe "Navigation IA (MiClassrooms signed-in shell)", type: :system do
  let(:shared_workspace) { create(:workspace, slug: "miclassrooms", name: "MiClassrooms", personal: false) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    shared_workspace
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared_workspace.slug)
    allow(Rails.configuration.x.tenancy).to receive(:shared_join_role).and_return("viewer")
    allow(Rails.configuration.x.tenancy).to receive(:workspace_creation).and_return(:disabled)
  end

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
  end

  describe "signed-in viewer" do
    let(:user) { create(:user) }

    before do
      sign_in_via_form(user)
      visit root_path
    end

    it "shows the brand and account menu" do
      within("header nav") do
        expect(page).to have_link(I18n.t("application.name"), href: root_path)
      end
      expect(page).to have_css("#user-menu-button", visible: :all)
    end

    it "still shows About via the footer" do
      within("footer") do
        expect(page).to have_link(I18n.t("footer.about"))
      end
    end

    it "does NOT show the workspace switcher" do
      expect(page).to have_no_css("#workspace-switcher-button", visible: :all)
    end

    it "does NOT show the All workspaces link (the switcher's see-all companion)" do
      expect(page).to have_no_link(I18n.t("navigation.all_workspaces"))
    end

    it "does NOT show the Admin nav region" do
      expect(page).to have_no_css(
        "nav[aria-label=#{I18n.t("navigation.admin.aria_label").inspect}]", visible: :all
      )
      # Scoped to the header: "Admin" alone also appears in unrelated marketing
      # copy ("Admin-posted alerts...") further down the home page, so a
      # page-wide text check would false-fail on that unrelated match.
      within("header") do
        expect(page).to have_no_text(I18n.t("navigation.admin.label"))
      end
    end

    it "passes axe AAA on the signed-in shell (light + dark)" do
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  describe "signed-in admin" do
    let(:user) { create(:user) }

    before do
      sign_in_via_form(user)
      membership = user.memberships.find_by!(workspace: shared_workspace)
      membership.update!(role: Role.system_default!("admin"))
      visit root_path
    end

    it "shows the Admin nav region as a labeled navigation landmark" do
      expect(page).to have_css(
        "nav[aria-label=#{I18n.t("navigation.admin.aria_label").inspect}]", visible: :all
      )
      expect(page).to have_button(I18n.t("navigation.admin.label"), visible: :all)
    end

    it "reveals the populated Admin panel on click (product navigation phase)" do
      click_button I18n.t("navigation.admin.label")
      expect(page).to have_link(I18n.t("navigation.admin.buildings"), href: buildings_path)
      expect(page).to have_link(I18n.t("navigation.admin.announcements"), href: admin_announcements_path)
      expect(page).to have_link(I18n.t("navigation.admin.editor_assignments"), href: admin_editor_assignments_path)
      expect(page).to have_link(I18n.t("navigation.admin.bulk_upload"), href: new_admin_bulk_upload_path)
      expect(page).to have_link(I18n.t("navigation.admin.characteristic_display_rules"), href: admin_characteristic_display_rules_path)
      expect(page).to have_link(I18n.t("navigation.admin.unit_display_names"), href: admin_unit_display_names_path)
      expect(page).to have_link(I18n.t("navigation.admin.sync_scope_rules"), href: admin_sync_scope_rules_path)
    end

    it "still hides the workspace switcher and All workspaces link" do
      expect(page).to have_no_css("#workspace-switcher-button", visible: :all)
      expect(page).to have_no_link(I18n.t("navigation.all_workspaces"))
    end

    it "passes axe AAA with the Admin region present (light + dark)" do
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  describe "hiding is config-driven, not an accident of membership count" do
    # A shared-posture user who ALSO holds a membership in some other
    # workspace (e.g. a legacy membership from before this instance's fork
    # disabled workspace creation) would still have workspaces.size > 1 —
    # the switcher's own internal "nothing to switch to" check would not
    # suppress it. Proves the TenancyConfig.shared? gate at the render call
    # site (shared/_header, shared/_user_menu) is what's doing the hiding,
    # not incidental single-membership math.
    let(:user) { create(:user) }
    let!(:other_workspace_membership) do
      create(:membership, :owner, user: user, workspace: create(:workspace, personal: false))
    end

    before do
      sign_in_via_form(user)
      visit root_path
    end

    it "still hides the workspace switcher and All workspaces link" do
      expect(page).to have_no_css("#workspace-switcher-button", visible: :all)
      expect(page).to have_no_link(I18n.t("navigation.all_workspaces"))
    end
  end

  describe "workspace creation stays disabled end-to-end" do
    let(:user) { create(:user) }

    it "the workspaces index shows no New workspace link when visited directly" do
      sign_in_via_form(user)
      visit workspaces_path
      expect(page).to have_no_link(I18n.t("workspaces.index.new_workspace"))
    end
  end
end
