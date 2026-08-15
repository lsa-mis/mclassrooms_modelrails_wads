# frozen_string_literal: true

require "rails_helper"

RSpec.describe UnattachedBlobsSweepJob do
  include ActiveJob::TestHelper

  def build_blob(filename)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("data"), filename: filename, content_type: "image/png"
    )
  end

  it "purges unattached blobs older than the grace period" do
    old_orphan = travel_to(3.days.ago) { build_blob("old-orphan.png") }

    perform_enqueued_jobs { described_class.perform_now }

    expect(ActiveStorage::Blob.exists?(old_orphan.id)).to be(false)
  end

  it "leaves recent unattached blobs alone (in-flight direct uploads)" do
    fresh_orphan = build_blob("fresh-orphan.png")

    perform_enqueued_jobs { described_class.perform_now }

    expect(ActiveStorage::Blob.exists?(fresh_orphan.id)).to be(true)
  end

  it "never touches attached blobs, regardless of age" do
    user = travel_to(3.days.ago) do
      create(:user, :with_avatar)
    end

    perform_enqueued_jobs { described_class.perform_now }

    expect(user.reload.avatar).to be_attached
  end
end
