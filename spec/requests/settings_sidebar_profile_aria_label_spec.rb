# frozen_string_literal: true

require "rails_helper"

# Regression spec: the account (personal) "Profile" sidebar link must carry a
# distinguishing aria-label so screen readers can tell it apart from the
# workspace-org "Profile" link that a user also sees when switching context.
#
# Without an explicit aria-label the link announces as bare "Profile" — identical
# to the org link — which fails the WCAG 2.4.6 / 1.3.1 distinctiveness requirement.
# The fix adds `aria_label: t("settings.sidebar.aria_labels.profile_personal")`
# to the personal-context render in shared/_settings_sidebar_items.html.erb.
#
# Uses Capybara.string (no browser) to parse the real rendered HTML — matching
# the pattern in spec/requests/settings_sidebar_visibility_spec.rb. Nokogiri
# backs the assertion so we never regex against raw response.body.
RSpec.describe "Settings sidebar account Profile aria-label", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  def settings_sidebar
    Capybara.string(response.body)
            .find("aside[aria-label='#{I18n.t("settings.sidebar.aria_label")}']")
  end

  def expected_aria_label
    I18n.t("settings.sidebar.aria_labels.profile_personal")
  end

  # GET /account/profile/edit renders the settings layout with the personal
  # workspace as Current.workspace (via PersonalWorkspaceContext), so
  # settings_context_kind returns :personal and the account items render.
  describe "GET /account/profile/edit (personal context)" do
    before { get edit_settings_profile_path }

    it "renders the account Profile link with a distinguishing aria-label" do
      expect(settings_sidebar).to have_link(
        I18n.t("settings.sidebar.items.profile"),
        href: edit_settings_profile_path
      )

      profile_link = settings_sidebar.find_link(
        I18n.t("settings.sidebar.items.profile"),
        href: edit_settings_profile_path
      )

      expect(profile_link["aria-label"]).to eq(expected_aria_label)
    end

    it "aria-label is not nil or blank" do
      profile_link = settings_sidebar.find_link(
        I18n.t("settings.sidebar.items.profile"),
        href: edit_settings_profile_path
      )

      expect(profile_link["aria-label"]).to be_present
    end
  end
end
