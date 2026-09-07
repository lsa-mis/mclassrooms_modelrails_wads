# frozen_string_literal: true

require "rails_helper"
require_relative "../../db/migrate/20260902120000_cap_never_notification_retention"

# The migration is a best-effort backfill (the reader in NotificationPreferences
# is the invariant), so what matters is that it touches exactly the rows it
# should and is safe to run twice.
RSpec.describe CapNeverNotificationRetention do
  def run_up
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  def stored_retention(prefs)
    ActiveRecord::Base.connection.select_value(
      "SELECT json_extract(notification_preferences, '$.retention_days') FROM user_preferences WHERE id = #{prefs.id}"
    )
  end

  def write_raw(prefs, hash)
    # update_column: bypass the value object so a nil or an absent key lands as-is.
    prefs.update_column(:notification_preferences, hash)
  end

  let(:base) { UserPreferences.new.notification_preferences }

  it "caps an explicit null (the retired Never choice) at 365" do
    prefs = create(:user).create_preferences!
    write_raw(prefs, base.merge("retention_days" => nil))

    run_up

    expect(stored_retention(prefs)).to eq(365)
  end

  it "leaves every allowed choice alone" do
    rows = NotificationPreferences::ALLOWED_RETENTION_DAYS.map do |days|
      prefs = create(:user).create_preferences!
      write_raw(prefs, base.merge("retention_days" => days))
      [ prefs, days ]
    end

    run_up

    rows.each { |prefs, days| expect(stored_retention(prefs)).to eq(days) }
  end

  it "leaves an absent key alone (the reader defaults it)" do
    prefs = create(:user).create_preferences!
    write_raw(prefs, base.except("retention_days"))

    run_up

    expect(stored_retention(prefs)).to be_nil
    expect(ActiveRecord::Base.connection.select_value(
      "SELECT json_type(notification_preferences, '$.retention_days') FROM user_preferences WHERE id = #{prefs.id}"
    )).to be_nil
  end

  it "does not create rows for users without preferences" do
    create(:user)

    expect { run_up }.not_to change(UserPreferences, :count)
  end

  it "is idempotent" do
    prefs = create(:user).create_preferences!
    write_raw(prefs, base.merge("retention_days" => nil))

    run_up
    run_up

    expect(stored_retention(prefs)).to eq(365)
  end
end
