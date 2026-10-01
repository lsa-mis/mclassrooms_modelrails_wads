# frozen_string_literal: true

require "rails_helper"

# The self-serve undo end to end: nav entry, confirm dialog, both themes (#812).
RSpec.describe "Settings — blocked senders", type: :system do
  let(:user) { create(:user) }
  let(:inviter) { create(:user, first_name: "Dana", last_name: "Sender") }
  let(:workspace) { create(:workspace) }

  before { sign_in_via_form(user) }

  it "is reachable from the settings nav and lifts a block end to end" do
    invitation = create(:invitation, email: user.email_address, invitable: workspace, invited_by: inviter)
    InvitationBlock.block!(inviter: inviter, email: user.email_address)
    expect(invitation.reload.suppressed_at).to be_present

    visit settings_passkeys_path
    click_link I18n.t("settings.sidebar.items.invitation_blocks")

    expect(page).to have_text("Dana Sender")
    # By visible text (no enable_aria_label); the closed dialog's twin is not visible.
    click_button I18n.t("settings.invitation_blocks.index.allow_button")
    within("dialog[open]") do
      click_button I18n.t("settings.invitation_blocks.index.allow_button")
    end

    expect(page).to have_text(I18n.t("settings.invitation_blocks.destroy.success"))
    # The row's disappearance first, then what replaces it.
    expect(page).to have_no_text("Dana Sender")
    expect(page).to have_text(I18n.t("settings.invitation_blocks.index.empty_state"))

    expect(InvitationBlock.exists?(inviter: inviter, email: user.email_address)).to be(false)
    expect(invitation.reload.suppressed_at).to be_nil
  end

  it "passes axe in both themes with a block listed" do
    create(:invitation_block, inviter: inviter, email: user.email_address)
    visit settings_invitation_blocks_path
    expect(page).to have_text("Dana Sender")

    scope = [ "#main-content" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "passes axe in both themes on the empty state" do
    visit settings_invitation_blocks_path
    expect(page).to have_text(I18n.t("settings.invitation_blocks.index.empty_state"))

    scope = [ "#main-content" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
