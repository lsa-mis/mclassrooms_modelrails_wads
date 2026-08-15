# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebauthnChallengesSweepJob, type: :job do
  it "deletes challenges past the grace window, consumed or not" do
    old_expired = WebauthnChallenge.create!(challenge: "old-expired", purpose: "authentication", expires_at: 2.days.ago)
    old_consumed = WebauthnChallenge.create!(challenge: "old-consumed", purpose: "registration", expires_at: 2.days.ago, consumed_at: 2.days.ago)

    described_class.perform_now

    expect(WebauthnChallenge.exists?(old_expired.id)).to be(false)
    expect(WebauthnChallenge.exists?(old_consumed.id)).to be(false)
  end

  it "keeps live challenges and recently-expired ones inside the grace window" do
    live = WebauthnChallenge.create!(challenge: "live", purpose: "authentication", expires_at: 4.minutes.from_now)
    recently_expired = WebauthnChallenge.create!(challenge: "recent", purpose: "authentication", expires_at: 10.minutes.ago)

    described_class.perform_now

    expect(WebauthnChallenge.exists?(live.id)).to be(true)
    expect(WebauthnChallenge.exists?(recently_expired.id)).to be(true)
  end
end
