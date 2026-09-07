# frozen_string_literal: true

require "rails_helper"

# #884: one preferences row per user, guaranteed by the database and reached
# through one path. Six call sites used to do `preferences || create_preferences!`
# with only a plain index behind them; two requests that both missed the read
# (the sign-in timezone beacon racing a settings write, two tabs, a system spec
# writing right after sign_in_via_form) each inserted, and has_one then returned
# whichever row it met first — the #949 flake.
RSpec.describe User, "#preferences!" do
  let(:user) { create(:user) }

  it "creates the row once and hands back the same row afterwards" do
    first = user.preferences!
    expect(first).to be_persisted
    expect(user.preferences!).to eq(first)
    expect(User.find(user.id).preferences!).to eq(first)
    expect(UserPreferences.where(user_id: user.id).count).to eq(1)
  end

  it "finds the row a racing writer inserted instead of inserting a second one" do
    raced = UserPreferences.create!(user: user)
    expect(user.reload.preferences!).to eq(raced)
    expect(UserPreferences.where(user_id: user.id).count).to eq(1)
  end

  it "is backed by a unique index, so a second row cannot exist" do
    user.preferences!
    expect { UserPreferences.insert!({ user_id: user.id, created_at: Time.current, updated_at: Time.current }) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
