class AddSupersededAtToMagicLinkTokens < ActiveRecord::Migration[8.1]
  # Redemption and supersession both set consumed_at; this tells them apart (#1083).
  def change
    add_column :magic_link_tokens, :superseded_at, :datetime
  end
end
