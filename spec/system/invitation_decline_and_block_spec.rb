require "rails_helper"

RSpec.describe "Invitation decline and block", type: :system do
  let(:inviter) { create(:user) }
  let(:invitation) { create(:invitation, invited_by: inviter) }

  it "points at the email link instead of offering a bearer block (#951)" do
    visit decline_invitation_path(token: invitation.token)

    # The non-client half of the copy branch T28 pins; without it, swapping the
    # two branches leaves only T28 red.
    expect(page).to have_content(
      I18n.t("invitation_declines.show.body",
             workspace: invitation.invitable.name, inviter: inviter.email_address)
    )
    expect(page).to have_content(
      I18n.t("invitation_declines.show.block_hint", inviter: inviter.email_address)
    )
    expect(page).to have_button(I18n.t("invitation_declines.show.confirm")) # positive anchor
    expect(page).to have_no_css("[data-controller='modal']")
    expect(axe_violations_in_both_themes).to be_empty
  end

  # Scoped: `with_viewport`'s ensure restores the suite default, so a leaked
  # narrow viewport can't reframe later specs in this parallel worker. The axe
  # assertion INSIDE the block covers the 320px state; the teardown audit then
  # covers the same page at the restored desktop width.
  it "reflows at 320px with no horizontal scroll (T21c)" do
    with_viewport(320, 800) do
      visit decline_invitation_path(token: invitation.token)
      expect(page.evaluate_script(
        "document.documentElement.scrollWidth <= document.documentElement.clientWidth"
      )).to be(true)
      expect(axe_violations_in_both_themes).to be_empty
    end
  end

  # The T21c reflow assertion above is data-dependent: it renders the inviter's
  # email, and the factory generates addresses of varying length, so it caught
  # this only when the generated one happened to be long enough. It failed twice
  # on main that way. This pins the same property with the length made explicit,
  # so the defect cannot go back to being intermittent.
  it "reflows at 320px even when the inviter's email is long (T21c)" do
    long_inviter = create(:user, email_address: "verylongfirstname.verylonglastname@some-quite-long-company-domain.example.com")
    long_invitation = create(:invitation, invited_by: long_inviter)

    with_viewport(320, 800) do
      visit decline_invitation_path(token: long_invitation.token)
      overflow = page.evaluate_script(
        "document.documentElement.scrollWidth - document.documentElement.clientWidth"
      )
      expect(overflow).to be <= 0, "page overflows its 320px viewport by #{overflow}px"
    end
  end

  it "offers no block hint on a magic-link invitation (anchored absence)" do
    bearer = create(:invitation, :magic_link, invited_by: inviter)
    visit decline_invitation_path(token: bearer.token)
    expect(page).to have_button(I18n.t("invitation_declines.show.confirm")) # positive anchor
    expect(page).to have_no_content(I18n.t("invitation_mailer.invite.block_action"))
  end

  it "blocks from the signed link in the invitation email, keyboard only, and states the outcome" do
    InvitationMailer.with(invitation: invitation).invite.deliver_now
    text = ActionMailer::Base.deliveries.last.text_part.body.decoded
    url = text[%r{https?://\S+/invitation_block\?token=\S+}]
    expect(url).to be_present

    visit URI.parse(url).request_uri
    expect(page).to have_css("h1", text: I18n.t("invitation_blocks.show.title", inviter: inviter.email_address))
    expect(axe_violations_in_both_themes).to be_empty

    button_text = I18n.t("invitation_blocks.show.button", inviter: inviter.email_address)
    reached = 20.times.any? do
      cdp_press("Tab")
      page.evaluate_script("document.activeElement.textContent").strip == button_text
    end
    expect(reached).to be(true), "Tab never reached the block button"
    cdp_press("Enter")

    expect(page).to have_css("h1", text: I18n.t("invitation_blocks.create.blocked_title", inviter: inviter.email_address))
    expect(invitation.reload).to be_declined
    expect(InvitationBlock.exists?(inviter_id: inviter.id, email: invitation.email)).to be(true)
    expect(axe_violations_in_both_themes).to be_empty
  end
end
