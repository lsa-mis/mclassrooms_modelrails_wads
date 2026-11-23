class AddPendingJoinLinkTokenToAuthentications < ActiveRecord::Migration[8.1]
  # Reshape 2b: new-user-via-link flow parks the workspace join-link token
  # on the email Authentication during deferred signup (same pattern as the
  # existing pending_invitation_token), then claims it at email verification.
  def change
    add_column :authentications, :pending_join_link_token, :string
  end
end
