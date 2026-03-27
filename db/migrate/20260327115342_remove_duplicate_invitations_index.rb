class RemoveDuplicateInvitationsIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :invitations, name: "index_invitations_on_invitable_type_and_invitable_id"
  end
end
