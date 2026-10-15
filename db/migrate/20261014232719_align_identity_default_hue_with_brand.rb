class AlignIdentityDefaultHueWithBrand < ActiveRecord::Migration[8.1]
  TABLES = %i[users workspaces].freeze

  def up
    TABLES.each do |table|
      change_column_default table, :primary_color, from: 210, to: 252
      execute "UPDATE #{table} SET primary_color = 252 WHERE primary_color = 210"
    end
  end

  def down
    TABLES.each do |table|
      change_column_default table, :primary_color, from: 252, to: 210
      execute "UPDATE #{table} SET primary_color = 210 WHERE primary_color = 252"
    end
  end
end
