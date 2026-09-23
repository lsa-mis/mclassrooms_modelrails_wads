module Settings
  class InvitationBlocksController < ApplicationController
    layout "settings"

    def index
      @invitation_blocks = my_blocks.includes(:inviter).order(:created_at)
    end

    # No `authorize`: the scope IS the authorization. `my_blocks` is the only
    # door, so `find` raises RecordNotFound on anything else — a 404 rather
    # than a 403, because a 403 confirms the id names a real block and tells
    # the requester that an address they do not own has blocked someone.
    def destroy
      block = my_blocks.find(params[:id])
      InvitationBlock.unblock!(inviter: block.inviter, email: block.email)
      redirect_to settings_invitation_blocks_path, notice: t(".success")
    end

    private
      # Blocks are email-keyed and account-independent, so the reach is the
      # ADDRESS, not the user. Queryable because `email` is encrypted
      # deterministically. A block against a previous address is deliberately
      # absent — it never followed the user there.
      def my_blocks
        InvitationBlock.where(email: Current.user.email_address)
      end
  end
end
