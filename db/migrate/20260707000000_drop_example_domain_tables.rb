class DropExampleDomainTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :client_accesses, if_exists: true
    drop_table :documents, if_exists: true
    drop_table :resources, if_exists: true
    drop_table :project_memberships, if_exists: true
    drop_table :projects, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
