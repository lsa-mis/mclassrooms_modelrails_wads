class AddBeforeAfterToActivityLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :activity_logs, :before_after, :json
  end
end
