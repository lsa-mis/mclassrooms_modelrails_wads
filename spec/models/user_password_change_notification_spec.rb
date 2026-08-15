# frozen_string_literal: true

require "rails_helper"

# PasswordChangedNotifier existed unwired: app/docs/developer/notifications.md
# documented it as firing on User#password_digest change, but nothing delivered
# it (2026-08-12 reauth-defaults panel). The model callback makes the docs true
# for every path that touches the digest — settings change, reset, removal.
RSpec.describe User, "password-change notification", type: :model do
  let(:user) { create(:user) }

  it "delivers PasswordChangedNotifier when the password changes" do
    expect {
      user.update!(password: "AnotherSecureP@ss1!", password_confirmation: "AnotherSecureP@ss1!")
    }.to change { Noticed::Event.where(type: "PasswordChangedNotifier").count }.by(1)
  end

  it "delivers when the password is removed (digest cleared)" do
    expect {
      user.update!(password_digest: nil)
    }.to change { Noticed::Event.where(type: "PasswordChangedNotifier").count }.by(1)
  end

  it "does not deliver on account creation" do
    expect {
      create(:user)
    }.not_to change { Noticed::Event.where(type: "PasswordChangedNotifier").count }
  end

  it "does not deliver on unrelated updates" do
    expect {
      user.update!(first_name: "Renamed")
    }.not_to change { Noticed::Event.where(type: "PasswordChangedNotifier").count }
  end
end
