require "rails_helper"

RSpec.describe "Noticed gem setup" do
  it "loads Noticed::Event constant" do
    expect { Noticed::Event }.not_to raise_error
  end

  it "creates noticed_events table with expected columns" do
    expect(ActiveRecord::Base.connection.tables).to include("noticed_events")
    columns = ActiveRecord::Base.connection.columns("noticed_events").map(&:name)
    expect(columns).to include("type", "params", "record_type", "record_id", "created_at", "updated_at")
  end

  it "creates noticed_notifications table with expected columns" do
    expect(ActiveRecord::Base.connection.tables).to include("noticed_notifications")
    columns = ActiveRecord::Base.connection.columns("noticed_notifications").map(&:name)
    expect(columns).to include("type", "event_id", "recipient_type", "recipient_id", "read_at", "seen_at")
  end
end
