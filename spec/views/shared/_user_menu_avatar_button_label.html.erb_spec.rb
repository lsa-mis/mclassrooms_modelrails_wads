require "rails_helper"

RSpec.describe "shared/_user_menu_avatar_button_label.html.erb", type: :view do
  let(:user) { create(:user, first_name: "Dave", last_name: "Chmura") }

  it "renders a sr-only span with the plain aria-label text when there are no unread" do
    render partial: "shared/user_menu_avatar_button_label", locals: { user: user }
    expect(rendered).to include('id="user_menu_button_label"')
    expect(rendered).to include('class="sr-only"')
    expect(rendered).to include("User menu for Dave Chmura")
  end

  it "includes the count and severity phrase when unread > 0" do
    PasswordChangedNotifier.with(record: user).deliver(user)
    render partial: "shared/user_menu_avatar_button_label", locals: { user: user }
    expect(rendered).to match(/User menu for Dave Chmura\. 1 unread notification, including a security alert\./)
  end

  it "accepts a pre-computed summary local and does not requery" do
    summary = { count: 2, severity: :warning }
    expect(user).not_to receive(:unread_notification_breakdown)
    render partial: "shared/user_menu_avatar_button_label",
           locals: { user: user, summary: summary }
    expect(rendered).to include("2 unread notifications")
  end
end
