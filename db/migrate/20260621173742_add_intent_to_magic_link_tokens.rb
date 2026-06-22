class AddIntentToMagicLinkTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :magic_link_tokens, :intent, :string
  end
end
