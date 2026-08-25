# frozen_string_literal: true

require "rails_helper"

# #745 (+#736/#742, same surface): the toggle family's screen-reader
# semantics, pinned on notification preferences — the settings page that
# renders every variant (plain, help-text, disabled always-on).
RSpec.describe "Toggle semantics (notification preferences)", type: :system do
  let(:user) { create(:user) }
  let(:security_name) { "notification_preferences[notification_types][security]" }

  before do
    sign_in_via_form(user)
    visit edit_settings_notification_preferences_path
  end

  def security_input
    find("input[name='#{security_name}'][type='checkbox']", visible: :all)
  end

  it "gives the security toggle an accessible name equal to the row title — help text described, never doubled in" do
    title = I18n.t("notifications.preferences.notification_types.items.security.title")
    expect(security_input["aria-label"]).to eq(title)

    describedby = security_input["aria-describedby"]
    expect(describedby).to be_present
    expect(find("##{describedby}", visible: :all).text).to eq(
      I18n.t("notifications.preferences.notification_types.always_on")
    )
  end

  it "keeps the always-on row discoverable: aria-disabled and focusable, not natively disabled" do
    expect(security_input["aria-disabled"]).to eq("true")
    expect(security_input.disabled?).to be(false)

    page.execute_script("document.querySelector(\"input[name='#{security_name}']\").focus()")
    expect(page.evaluate_script("document.activeElement.name")).to eq(security_name)
  end

  it "blocks interaction on the aria-disabled toggle — checked state survives a click" do
    expect(security_input).to be_checked
    page.execute_script("document.querySelector(\"input[name='#{security_name}']\").click()")
    expect(security_input).to be_checked
  end

  it "still allows toggling an enabled row" do
    mentions_name = "notification_preferences[notification_types][account_access]"
    input = find("input[name='#{mentions_name}'][type='checkbox']", visible: :all)
    initial = input.checked?
    page.execute_script("document.querySelector(\"input[name='#{mentions_name}']\").click()")
    expect(input.checked?).to eq(!initial)
  end

  it "passes axe in both themes with the new toggle markup" do
    scope = [ "#main-content" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
