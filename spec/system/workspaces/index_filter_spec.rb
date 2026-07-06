require "rails_helper"

# The workspaces index renders a user's own memberships in full; the client-side
# filter (workspace_filter_controller.js) hides non-matching rows in the
# "Other workspaces" list without a server round-trip.
RSpec.describe "Workspaces index client-side filter", type: :system do
  let(:user) { create(:user) }

  before do
    # A clearly-most-recent workspace becomes the pinned "current" row, which is
    # outside the filter, so the named workspaces below land in the filterable
    # "other" list (and there are >= 8 of them, so the filter renders).
    create(:membership, :owner, user: user,
           workspace: create(:workspace, name: "Zzz Current"), last_accessed_at: Time.current)
    %w[Apple Banana Cherry Date Elderberry Fig Grape Kiwi].each do |name|
      create(:membership, :owner, user: user, workspace: create(:workspace, name: name))
    end

    sign_in_via_form(user)
    visit workspaces_path
  end

  it "hides non-matching rows as you type into the filter" do
    filter = I18n.t("workspaces.index.filter.label")
    expect(page).to have_text("Apple")
    expect(page).to have_text("Banana")

    fill_in filter, with: "apple"

    expect(page).to have_text("Apple")
    expect(page).to have_no_text("Banana")
    expect(page).to have_no_text(I18n.t("workspaces.index.filter.empty"))
  end

  it "reveals the empty message when nothing matches" do
    fill_in I18n.t("workspaces.index.filter.label"), with: "no-such-workspace"

    expect(page).to have_text(I18n.t("workspaces.index.filter.empty"))
    expect(page).to have_no_text("Apple")
  end
end
