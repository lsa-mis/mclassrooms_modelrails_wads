class InvitationBlocksController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to root_path, alert: t("invitation_blocks.create.rate_limited") }

  # GET /invitation_block?token= — confirmation only. The signed token exists
  # in one place, the "Don't invite me again" link in the invitee's own
  # invitation email, which is the mailbox proof (#951).
  def show
    @invitation = find_blockable_invitation or return
  end

  # POST /invitation_block — performs the block and renders the outcome in the
  # document: a redirect-and-toast alone is not announced.
  def create
    @invitation = find_blockable_invitation or return

    @invitation.decline_and_block!
    render :create, status: :ok
  rescue ActiveRecord::RecordInvalid
    # Only the raced decline! reaches here — block! absorbs its own signals —
    # and the block IS saved, so the page claims the block, not the decline.
    render :already_processed, status: :ok
  end

  private

  # Absolute key: this filter serves both #show and #create. `expired?` keeps
  # this endpoint in step with the decline flow (an expired invitation is not
  # declined-and-blocked, so no decline notification fires for a lapsed one);
  # the has_invitee? refusal is this endpoint's own: nothing to block for on a
  # magic link, and decline_and_block! raises on one. The copy is this flow's
  # own because a spent link (a refresh after a successful block) lands here
  # too, and "invalid" would be untrue of it.
  def find_blockable_invitation
    invitation = Invitation.find_by_token_for(:block_confirmation, params[:token])

    if invitation.nil? || !invitation.pending? || invitation.expired? || !invitation.has_invitee?
      redirect_to root_path, alert: t("invitation_blocks.invalid")
      return nil
    end

    invitation
  end
end
