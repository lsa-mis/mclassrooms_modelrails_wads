require "rails_helper"

RSpec.describe "shared/_user_menu_avatar_button.html.erb", type: :view do
  let(:user) { create(:user, first_name: "Dave", last_name: "Chmura") }

  it "renders a button with id #user-menu-button (stable test hook)" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('id="user-menu-button"')
    expect(rendered).to include('aria-haspopup="true"')
    expect(rendered).to include('aria-expanded="false"')
    expect(rendered).to include('aria-controls="user-menu"')
  end

  it "carries a static aria-label naming the user (D1: bell aria moved to bell link)" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to match(/aria-label="Open user menu for Dave Chmura"/)
  end

  it "does NOT carry aria-labelledby pointing to a broadcast-replaceable frame (D1)" do
    # Pre-D1 the avatar button delegated its accessible name via
    # aria-labelledby to a sibling sr-only span inside a broadcast frame
    # so notification arrivals could swap the count without detaching the
    # button. D1 moves notifications off the avatar entirely — the avatar
    # carries a static identity-only aria-label.
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).not_to include('aria-labelledby="user_menu_button_label"')
  end

  it "nests the avatar image inside the button" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to include('id="user_avatar_header"')
  end

  it "does NOT render the notifications-bell overlay (D1: bell relocated to header)" do
    # An unread notification used to render the severity-colored bell overlay
    # inside the avatar button. After D1 the overlay lives on the standalone
    # header bell link instead.
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).not_to include('notifications_bell_indicator_frame')
    expect(rendered).not_to include('data-bell-severity')
  end

  it "applies the AAA focus ring (ring-2, ring-offset-2, ring-interactive-focus)" do
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to match(/focus:ring-2/)
    expect(rendered).to match(/focus:ring-offset-2/)
    expect(rendered).to match(/focus:ring-interactive-focus/)
  end

  it "renders a chevron-down affordance so the avatar reads as a menu trigger" do
    # Wathan's D1 design-panel note: a bare avatar reads as a static
    # identity badge, not as an interactive control. The chevron is the
    # universal "this opens a menu" hint and matches the workspace
    # switcher's pattern. data-test attribute provides a stable selector
    # without baking icon-internal SVG markup into the spec.
    render partial: "shared/user_menu_avatar_button", locals: { user: user }
    expect(rendered).to have_css('#user-menu-button [data-test="user-menu-chevron"]')
  end
end
