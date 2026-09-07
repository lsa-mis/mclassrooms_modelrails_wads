# frozen_string_literal: true

require "rails_helper"

# #884: a user's preferences row is reached through User#preferences! and
# nothing else. Six `preferences || create_preferences!` sites each raced the
# others into a second row that has_one then hid; the unique index refuses the
# row now, and this keeps the seventh site from being written.
RSpec.describe "One preferences creation path" do
  it "has no check-then-create of user preferences outside User#preferences!" do
    offenders = Dir.glob(Rails.root.join("app/**/*.{rb,erb}")).select do |file|
      next false if file.end_with?("app/models/user.rb")

      without_comments(File.read(file)).match?(/create_preferences!|build_preferences|UserPreferences\.(create|find_or_create|create_or_find)/)
    end

    expect(offenders).to be_empty,
      "Reach a user's preferences through User#preferences! (#884):\n  #{offenders.join("\n  ")}"
  end
end
