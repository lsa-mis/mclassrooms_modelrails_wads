class CreateUserPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :user_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :theme, default: "system"
      t.string :locale
      t.string :timezone
      t.string :docs_mode

      t.timestamps
    end
  end
end
