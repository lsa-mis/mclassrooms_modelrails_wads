require "rails_helper"

# Follows the house pattern for rake specs — see spec/tasks/admin_spec.rb and
# spec/tasks/tenancy_spec.rb. Do NOT replace Rake.application with a fresh
# instance: it is a process global that nothing restores, and the other rake
# specs depend on whatever is there.
RSpec.describe "panoramas:render_flat" do
  include ActiveJob::TestHelper

  let(:workspace) { create(:workspace, slug: "backfill-ws", personal: false) }
  let(:building)  { create(:building, workspace: workspace) }

  before(:all) { Rails.application.load_tasks }
  before { Rake::Task["panoramas:render_flat"].reenable }

  # Snapshot and RESTORE — deleting would destroy a value set outside the suite.
  around do |example|
    saved = ENV.to_h.slice("WORKSPACE", "INLINE", "DRY_RUN", "FORCE", "LIMIT", "ROOM")
    example.run
  ensure
    %w[WORKSPACE INLINE DRY_RUN FORCE LIMIT ROOM].each { |k| ENV.delete(k) }
    saved.each { |k, v| ENV[k] = v }
  end

  def run(**env)
    env.each { |k, v| ENV[k.to_s] = v.to_s }
    Rake::Task["panoramas:render_flat"].invoke
  end

  it "renders rooms whose flat render is missing" do
    room = create(:room, :with_equirect_panorama, building: building, workspace: workspace)

    run(WORKSPACE: workspace.slug, INLINE: "1")

    expect(room.reload.flat_panorama).to be_attached
  end

  it "touches nothing on a dry run" do
    room = create(:room, :with_equirect_panorama, building: building, workspace: workspace)

    run(WORKSPACE: workspace.slug, INLINE: "1", DRY_RUN: "1")

    expect(room.reload.flat_panorama).not_to be_attached
  end

  it "renders only the room named by ROOM" do
    target = create(:room, :with_equirect_panorama, building: building, workspace: workspace)
    other  = create(:room, :with_equirect_panorama, building: building, workspace: workspace)

    run(WORKSPACE: workspace.slug, INLINE: "1", ROOM: target.rmrecnbr)

    expect(target.reload.flat_panorama).to be_attached
    expect(other.reload.flat_panorama).not_to be_attached
  end

  it "skips fresh rooms unless forced" do
    room = create(:room, :with_equirect_panorama, building: building, workspace: workspace)
    RenderFlatPanoramaJob.perform_now(room.id)
    original = room.reload.flat_panorama.blob.id

    run(WORKSPACE: workspace.slug, INLINE: "1")
    expect(room.reload.flat_panorama.blob.id).to eq(original)

    Rake::Task["panoramas:render_flat"].reenable
    run(WORKSPACE: workspace.slug, INLINE: "1", FORCE: "1")
    expect(room.reload.flat_panorama.blob.id).not_to eq(original)
  end

  it "enqueues rather than rendering when INLINE is absent" do
    room = create(:room, :with_equirect_panorama, building: building, workspace: workspace)
    clear_enqueued_jobs

    expect { run(WORKSPACE: workspace.slug) }
      .to have_enqueued_job(RenderFlatPanoramaJob).with(room.id)
  end

  # ONE REQUIRED DEVIATION FROM THE BRIEF: RenderFlatPanoramaJob#permanently_failed?
  # skips any room whose SOURCE (panorama) blob carries a flat_render_failed_at
  # tombstone matching the current source key. Candidate selection alone (the
  # `next true if force` in FlatPanoramaTasks.candidates) is not enough to force
  # a re-render of such a room — the job would still see the tombstone and
  # silently skip. FORCE must also clear the tombstone before invoking the job;
  # see the comment on FlatPanoramaTasks.clear_tombstone! for why that lives in
  # the rake task rather than the job.
  #
  # Built via a real :with_panorama room (200x200, non-2:1): the equirect
  # aspect-ratio guard in Panorama::Rectilinear raises NotEquirectangular, which
  # the job's discard_on handler stamps as a permanent failure — the same
  # tombstone a genuinely bad production photo would leave behind. The source
  # stays bad throughout this example on purpose: the point is proving the
  # render is genuinely RE-ATTEMPTED under FORCE (a fresh failure timestamp),
  # not merely re-selected as a candidate every run regardless of FORCE (which
  # it already is, since flat_panorama never attached).
  it "re-renders a room whose render previously failed when FORCE is set" do
    room = create(:room, :with_panorama, building: building, workspace: workspace)
    RenderFlatPanoramaJob.perform_now(room.id)
    first_stamp = room.reload.panorama.blob.metadata["flat_render_failed_at"]
    expect(first_stamp).to be_present
    expect(room.flat_panorama).not_to be_attached

    # Without FORCE, the tombstone guard skips the room outright: the render
    # is never re-attempted, so the failure timestamp does not move even
    # though the room is (still) selected as a candidate every run.
    run(WORKSPACE: workspace.slug, INLINE: "1")
    expect(room.reload.panorama.blob.metadata["flat_render_failed_at"]).to eq(first_stamp)

    # FORCE clears the tombstone before invoking the job, so the (still bad)
    # source is genuinely re-attempted and fails again with a FRESH stamp.
    Rake::Task["panoramas:render_flat"].reenable
    travel 1.hour do
      run(WORKSPACE: workspace.slug, INLINE: "1", FORCE: "1")
    end
    expect(room.reload.panorama.blob.metadata["flat_render_failed_at"]).not_to eq(first_stamp)
  end
end
