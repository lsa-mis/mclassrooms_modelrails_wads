# frozen_string_literal: true

require "rails_helper"

# #831/#822: the settings/sessions page carries two lists — active devices and
# recent account activity — and they have to read as one page. Every assertion
# here is geometry or a computed value the user can see (a stacked line box, a
# 20px row inset, a shared text left edge), never a Tailwind class name: the
# classes are the implementation, and a fork restyles them first.
RSpec.describe "Settings sessions — card convergence", type: :system do
  let(:user) { create(:user, first_name: "Sam", last_name: "Session") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    sign_in_via_form(user)
    expect(page).to have_css("#user-menu-button")
    user.sessions.create!(user_agent: "Mozilla/5.0 (Windows NT 10.0) Firefox/130.0", ip_address: "10.0.0.8")
    create(:activity_log, :security, actor: user, action: "user.password_changed")
  end

  it "stacks an activity row's label above its timestamp at phone width" do
    with_viewport(320, 800) do
      visit settings_sessions_path
      expect(page).to have_css("[data-testid='account-activity-item']")

      stacked = page.evaluate_script(<<~JS)
        (() => {
          const row   = document.querySelector("[data-testid='account-activity-item']");
          const label = row.querySelector("span");
          const time  = row.querySelector("time");
          return label.getBoundingClientRect().bottom <= time.getBoundingClientRect().top + 1;
        })()
      JS

      expect(stacked).to be(true),
        "At 320px the activity label should sit ABOVE its timestamp, not beside it."

      # Inline, and INSIDE the block: with_viewport's `ensure` restores the
      # 1400px suite default before the teardown audit runs (#912), so the
      # stacked narrow layout this example exists to protect is audited here
      # or nowhere.
      page.execute_script("document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())")
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations at 320px:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  it "gives an activity row the canonical card rhythm and hierarchy at desktop" do
    visit settings_sessions_path
    expect(page).to have_css("[data-testid='account-activity-item']")

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const row      = document.querySelector("[data-testid='account-activity-item']");
        const label    = row.querySelector("span");
        const heading  = document.querySelector("[data-testid='account-activity-item']")
                                 .closest("section").querySelector("h2");
        const device   = document.querySelector("[data-testid='device-list'] li p");
        const style    = getComputedStyle(row);
        const lstyle   = getComputedStyle(label);
        const dstyle   = getComputedStyle(device);
        return {
          paddingTop:    style.paddingTop,
          paddingBottom: style.paddingBottom,
          headingDelta:  Math.abs(label.getBoundingClientRect().left -
                                  heading.getBoundingClientRect().left),
          labelWeight:   lstyle.fontWeight,
          deviceWeight:  dstyle.fontWeight,
          labelColor:    lstyle.color,
          deviceColor:   dstyle.color,
          sideBySide:    row.querySelector("time").getBoundingClientRect().left >
                         label.getBoundingClientRect().right
        };
      })()
    JS

    # 1 + 2: one rhythm for the whole card — the canonical preferences row and
    # this card's own header are both py-5, so a populated row cannot be py-4
    # while the empty state next to it is py-5.
    expect(metrics["paddingTop"]).to eq("20px")
    expect(metrics["paddingBottom"]).to eq("20px")
    # The label shares the card heading's text left edge (subpixel tolerance —
    # exact float equality on a rect is a flake waiting to happen).
    expect(metrics["headingDelta"]).to be <= 1
    # 4: the card's content is not lighter than the device list's content.
    expect(metrics["labelWeight"]).to eq(metrics["deviceWeight"])
    expect(metrics["labelColor"]).to eq(metrics["deviceColor"])
    # 5, the other half: the stack at 320px is a NARROW-width behaviour. Losing
    # `sm:flex-row` would keep the phone example green while making every row
    # two lines forever, so the desktop side is pinned too.
    expect(metrics["sideBySide"]).to be(true),
      "At desktop the timestamp should sit to the RIGHT of the label, not below it."
  end

  it "shares one text left edge between the device list and the activity card" do
    visit settings_sessions_path
    expect(page).to have_css("[data-testid='account-activity-item']")

    jag = page.evaluate_script(<<~JS)
      (() => {
        const device   = document.querySelector("[data-testid='device-list'] li p");
        const activity = document.querySelector("[data-testid='account-activity-item'] span");
        return Math.abs(device.getBoundingClientRect().left -
                        activity.getBoundingClientRect().left);
      })()
    JS

    expect(jag).to be <= 1,
      "Device-row text and activity-row text should start at the same x; " \
      "they were #{jag}px apart."
  end

  it "gives the device list its own heading, in a card, accessibly in both themes" do
    visit settings_sessions_path

    device_section = page.find("[data-testid='device-list']").find(:xpath, "ancestor::section[1]")
    expect(device_section).to have_css("h2", text: I18n.t("settings.sessions.index.devices_heading"))

    page.execute_script("document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())")
    axe_options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
