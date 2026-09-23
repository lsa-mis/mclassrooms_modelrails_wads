require "rails_helper"

# #812. Blocks are created from the unauthenticated decline page — including by
# people with no account — and removal had only an operator door: a
# two-statement console recipe in the troubleshooting doc. A person who
# mis-clicked had no undo they could reach themselves.
#
# The reach is the ADDRESS, not the account: blocks are email-keyed and
# account-independent, so this lists the blocks naming the signed-in user's own
# address. A block made before they had an account shows up; one made against a
# previous address deliberately does not (it never followed them).
RSpec.describe "Settings::InvitationBlocks", type: :request do
  let(:user) { create(:user) }
  let(:inviter) { create(:user, first_name: "Dana", last_name: "Sender") }

  describe "unauthenticated access" do
    it "redirects GET /account/invitation_blocks to sign in" do
      get settings_invitation_blocks_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects DELETE /account/invitation_blocks/:id to sign in" do
      delete settings_invitation_block_path(create(:invitation_block))
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET index" do
    before { sign_in(user) }

    it "lists the blocks naming the signed-in user's address" do
      create(:invitation_block, inviter: inviter, email: user.email_address)

      get settings_invitation_blocks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dana Sender")
    end

    it "does not list a block against somebody else's address" do
      create(:invitation_block, inviter: inviter, email: "someone-else@example.com")

      get settings_invitation_blocks_path

      expect(response.body).not_to include("Dana Sender")
    end

    it "renders an empty state when the user has blocked nobody" do
      get settings_invitation_blocks_path

      expect(response).to have_http_status(:ok)
      # Compared as TEXT, not as a body substring: the copy carries an
      # apostrophe and curly quotes, which reach the response escaped.
      expect(Nokogiri::HTML(response.body).text)
        .to include(I18n.t("settings.invitation_blocks.index.empty_state"))
    end
  end

  describe "DELETE destroy" do
    before { sign_in(user) }

    it "removes the block and restores delivery from that sender" do
      workspace = create(:workspace)
      invitation = create(:invitation, email: user.email_address, invitable: workspace, invited_by: inviter)
      InvitationBlock.block!(inviter: inviter, email: user.email_address)
      block = InvitationBlock.find_by!(inviter: inviter, email: user.email_address)
      expect(invitation.reload.suppressed_at).to be_present

      delete settings_invitation_block_path(block)

      expect(response).to redirect_to(settings_invitation_blocks_path)
      expect(InvitationBlock.exists?(block.id)).to be(false)
      # The half a console recipe forgets: without it the stamped row stays
      # invisible to bulk_invite!'s duplicate check and every later invite
      # mints a duplicate instead of sending.
      expect(invitation.reload.suppressed_at).to be_nil
    end

    # Not-found, not forbidden: a refusal would confirm the id names a real
    # block, telling the requester that an address they do not own has blocked
    # someone. Scoping the `find` is what makes the two indistinguishable —
    # this app answers a missing record with its generic not-found alert, and
    # a Pundit refusal with a different alert and a different destination, so
    # asserting the ALERT is what proves the requester cannot tell them apart.
    it "answers a block belonging to another address as not-found, not forbidden" do
      block = create(:invitation_block, inviter: inviter, email: "not-mine@example.com")

      delete settings_invitation_block_path(block)

      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
      expect(InvitationBlock.exists?(block.id)).to be(true)
    end
  end
end
