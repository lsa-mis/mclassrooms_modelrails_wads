# frozen_string_literal: true

require "rails_helper"
require "rake"

# House rake-spec pattern (spec/tasks/flat_panoramas_rake_spec.rb): load_tasks
# in before(:all), reenable per example, snapshot-and-restore ENV. Warming is
# idempotent (processed is create-or-find), so the duplicate-action hazard
# load_tasks introduces is harmless here.
RSpec.describe "media:warm_variants" do
  let(:workspace) { create(:workspace, slug: "warm-rake-ws", personal: false) }
  let(:room)      { create(:room, workspace: workspace) }

  before(:all) { Rails.application.load_tasks }
  before { Rake::Task["media:warm_variants"].reenable }

  around do |example|
    saved = ENV["WORKSPACE"]
    example.run
  ensure
    ENV.delete("WORKSPACE")
    ENV["WORKSPACE"] = saved if saved
  end

  def run(slug)
    ENV["WORKSPACE"] = slug
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    Rake::Task["media:warm_variants"].invoke
    captured.string
  ensure
    $stdout = original
  end

  it "warms every declared variant for the workspace's assets" do
    asset = create(:media_asset, owner: room, workspace: workspace)

    run(workspace.slug)

    digests = %i[card thumb gallery full].map { |n| asset.image.variant(n).variation.digest }
    expect(asset.image.blob.variant_records.pluck(:variation_digest)).to match_array(digests)
  end

  it "aborts without WORKSPACE" do
    ENV.delete("WORKSPACE")

    expect { Rake::Task["media:warm_variants"].invoke }.to raise_error(SystemExit)
  end
end
