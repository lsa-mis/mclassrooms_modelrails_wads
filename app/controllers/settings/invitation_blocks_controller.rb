module Settings
  class InvitationBlocksController < ApplicationController
    layout "settings"

    def index
      @invitation_blocks = my_blocks.includes(:inviter).order(:created_at)
    end

    # No `authorize`: the scope is the authorization. A foreign id gets the same
    # not-found redirect as a missing one, so it confirms nothing (#812).
    def destroy
      block = my_blocks.find(params[:id])
      InvitationBlock.unblock!(inviter: block.inviter, email: block.email)
      redirect_to settings_invitation_blocks_path, notice: t(".success")
    end

    private
      # Keyed by address, not account; `email` is deterministically encrypted.
      def my_blocks
        InvitationBlock.where(email: Current.user.email_address)
      end
  end
end
