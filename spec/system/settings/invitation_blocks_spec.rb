# frozen_string_literal: true

require "rails_helper"

# #812. The end-to-end claim the issue makes: a person who mis-clicked "Don't
# invite me again" can undo it themselves, and delivery from that sender
# actually resumes. The request spec proves the write; this proves the door —
# the nav entry, the confirm dialog, and both themes under axe.
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
    # By visible text, not the aria-label: `Capybara.enable_aria_label` is not
    # set for this suite. The trigger and the dialog's confirm share that text,
    # but the closed <dialog> is not visible, so only the trigger matches here.
    click_button I18n.t("settings.invitation_blocks.index.allow_button")
    within("dialog[open]") do
      click_button I18n.t("settings.invitation_blocks.index.allow_button")
    end

    expect(page).to have_text(I18n.t("settings.invitation_blocks.destroy.success"))
    # Assert the disappearance before the arrival: the row must GO, and the
    # empty state is what replaces it.
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
