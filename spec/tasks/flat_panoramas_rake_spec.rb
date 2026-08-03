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
  # config/initializers/flat_panorama_callbacks.rb auto-enqueues
  # RenderFlatPanoramaJob on every panorama attach, including the ones the
  # :with_equirect_panorama/:with_panorama factory traits do in OTHER
  # examples in this file. The ActiveJob test adapter's queue is a process
  # global, not reset by transactional-fixture rollback, so a job left behind
  # by a prior example (with a since-reused SQLite rowid) can otherwise leak
  # into "enqueues rather than rendering when INLINE is absent" and inflate
  # its count. Start every example with a clean queue.
  before { clear_enqueued_jobs }

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

  # Same capture pattern as panoramas:flat_status's run_status below — needed
  # by the one example that asserts on the printed rendered/failed/skipped
  # counts, not just on room state.
  def run_capturing(**env)
    env.each { |k, v| ENV[k.to_s] = v.to_s }
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    Rake::Task["panoramas:render_flat"].invoke
    captured.string
  ensure
    $stdout = original
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

    # at_least(1), not the matcher's default exactly(1): `Rails.application.
    # load_tasks` (the house `before(:all)` pattern this file, admin_spec.rb,
    # and tenancy_spec.rb all use) re-`load`s every .rake file on each call,
    # and Rake APPENDS a redefined task's block to its existing actions
    # rather than replacing it — confirmed directly against Rake::Task's
    # @actions. Every OTHER top-level example group in spec/tasks/ that has
    # already run its own before(:all) by the time this example executes
    # (order is random) adds one more duplicate action to THIS task, so a
    # single #invoke can legitimately run the body more than once in the
    # same process. The task's own idempotence (fresh?/permanently_failed?
    # guards, RenderFlatPanoramaJob's own dedup) is what makes repeated runs
    # safe; asserting an exact enqueue count here would be asserting a
    # process-global fact this spec does not control.
    expect { run(WORKSPACE: workspace.slug) }
      .to have_enqueued_job(RenderFlatPanoramaJob).with(room.id).at_least(1).times
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
  # not merely re-selected as a candidate (FlatPanoramaTasks.candidates
  # EXCLUDES a tombstoned room outright unless force — see the "to render: 0
  # of 0" it prints below without FORCE).
  it "re-renders a room whose render previously failed when FORCE is set" do
    room = create(:room, :with_panorama, building: building, workspace: workspace)
    RenderFlatPanoramaJob.perform_now(room.id)
    first_stamp = room.reload.panorama.blob.metadata["flat_render_failed_at"]
    expect(first_stamp).to be_present
    expect(room.flat_panorama).not_to be_attached

    # Without FORCE the tombstoned room is not even a candidate — the render
    # is never attempted, so the failure timestamp does not move.
    run(WORKSPACE: workspace.slug, INLINE: "1")
    expect(room.reload.panorama.blob.metadata["flat_render_failed_at"]).to eq(first_stamp)

    # FORCE clears the tombstone before invoking the job, so the (still bad)
    # source is genuinely re-attempted and fails again with a FRESH stamp.
    Rake::Task["panoramas:render_flat"].reenable
    output = travel(1.hour) { run_capturing(WORKSPACE: workspace.slug, INLINE: "1", FORCE: "1") }
    expect(room.reload.panorama.blob.metadata["flat_render_failed_at"]).not_to eq(first_stamp)

    # The printed counts are the ONLY operator-visible signal (Mission
    # Control isn't mounted) — this is what the CRITICAL finding was about:
    # RenderFlatPanoramaJob swallows this room's NotEquirectangular failure
    # internally, so "perform_now did not raise" is not evidence of success.
    # A regression back to exception-based classification (or any
    # mis-bucketing) reports this as "rendered: 1 failed: 0", the exact
    # defect that finding raised. Room-state assertions alone (above) don't
    # catch that, since they were equally true under the old classification.
    expect(output).to include("rendered: 0")
    expect(output).to include("failed: 1")
  end

  # Every other example above builds rooms in exactly one workspace, so none
  # of them would fail if `Room.where(workspace: workspace)` were deleted
  # from FlatPanoramaTasks.scope. This is the one example that actually
  # exercises tenant isolation.
  it "only touches rooms in the requested WORKSPACE" do
    other_workspace = create(:workspace, slug: "other-backfill-ws", personal: false)
    other_building  = create(:building, workspace: other_workspace)
    other_room = create(:room, :with_equirect_panorama, building: other_building, workspace: other_workspace)
    room       = create(:room, :with_equirect_panorama, building: building, workspace: workspace)

    run(WORKSPACE: workspace.slug, INLINE: "1")

    expect(room.reload.flat_panorama).to be_attached
    expect(other_room.reload.flat_panorama).not_to be_attached
  end

  describe "LIMIT" do
    # LIMIT's HAPPY path had no coverage at all — only its two abort cases did.
    # Delete `candidates.first(limit)` and LIMIT=1 silently means "render
    # everything", which is the opposite of what an operator cautiously slicing
    # a first batch on production asked for.
    # Asserted on the PRINTED slice rather than by counting rendered rooms,
    # for the process-global reason spelled out at "enqueues rather than
    # rendering when INLINE is absent" above: repeated `Rails.application.
    # load_tasks` calls APPEND duplicate actions to this task, so one #invoke
    # can run the body more than once — and a second pass renders the room the
    # first pass's LIMIT held back, leaving both attached. The printed line is
    # immune to that (each pass prints its own honest numerator/denominator)
    # and is the direct evidence: delete `candidates.first(limit)` and the
    # first pass prints "to render: 2 of 2".
    it "renders only LIMIT of the outstanding rooms" do
      2.times { create(:room, :with_equirect_panorama, building: building, workspace: workspace) }

      output = run_capturing(WORKSPACE: workspace.slug, INLINE: "1", LIMIT: "1")

      expect(output).to include("to render:     1 of 2 stale/missing")
      expect(output).to include("rendered: 1")
    end

    # A typo (LIMIT=abc) or LIMIT=0 would otherwise silently become
    # `candidates.first(0)` — the run prints a plausible "to render: 0 of N"
    # and "enqueued: 0"/"rendered: 0" and does nothing, with no error at all.
    #
    # The MESSAGE, not a bare SystemExit: `abort` raises SystemExit, and so
    # does FlatPanoramaTasks.workspace!'s own abort — which runs FIRST, before
    # LIMIT is ever parsed. A bare `raise_error(SystemExit)` therefore passes
    # for a run that never reached the code under test at all.
    it "aborts on a non-numeric LIMIT rather than silently rendering nothing" do
      create(:room, :with_equirect_panorama, building: building, workspace: workspace)

      expect { run(WORKSPACE: workspace.slug, INLINE: "1", LIMIT: "abc") }
        .to raise_error(SystemExit, /LIMIT must be a positive integer, got "abc"/)
    end

    it "aborts on LIMIT=0 rather than silently rendering nothing" do
      create(:room, :with_equirect_panorama, building: building, workspace: workspace)

      expect { run(WORKSPACE: workspace.slug, INLINE: "1", LIMIT: "0") }
        .to raise_error(SystemExit, /LIMIT must be a positive integer, got "0"/)
    end
  end
end

RSpec.describe "panoramas:flat_status" do
  let(:workspace) { create(:workspace, slug: "status-ws", personal: false) }
  let(:building)  { create(:building, workspace: workspace) }

  before(:all) { Rails.application.load_tasks }
  before { Rake::Task["panoramas:flat_status"].reenable }

  # Snapshot and RESTORE, same as panoramas:render_flat above.
  around do |example|
    saved = ENV["WORKSPACE"]
    example.run
  ensure
    ENV.delete("WORKSPACE")
    ENV["WORKSPACE"] = saved if saved
  end

  def run_status
    ENV["WORKSPACE"] = workspace.slug
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    Rake::Task["panoramas:flat_status"].invoke
    captured.string
  ensure
    $stdout = original
  end

  # IMPORTANT 3: flat_status (including the orphan query) previously had no
  # coverage at all — the only verification was a smoke run returning
  # "orphaned flat: 0", which a broken query also returns. This exercises all
  # four room states the task's counts are supposed to keep disjoint.
  it "separates healthy, stale, tombstoned, and orphaned rooms" do
    healthy = create(:room, :with_equirect_panorama, building: building, workspace: workspace)
    RenderFlatPanoramaJob.perform_now(healthy.id)

    # Attached but with no stamps at all — mismatches source_blob_key/
    # projection, so it's stale, not healthy.
    create(:room, :with_equirect_panorama, :with_flat_panorama, building: building, workspace: workspace)

    tombstoned = create(:room, :with_panorama, building: building, workspace: workspace)
    RenderFlatPanoramaJob.perform_now(tombstoned.id)

    # A flat render with NO panorama at all — never joined into `scope`
    # (which requires panorama_attachment), so it must show up ONLY in the
    # orphan count and nowhere else.
    create(:room, :with_flat_panorama, building: building, workspace: workspace)

    output = run_status

    expect(output).to match(/^with panorama: 3$/)
    expect(output).to match(/^missing\/stale: 1$/)
    expect(output).to match(/^failed render: 1$/)
    expect(output).to match(/^orphaned flat: 1$/)
  end
end
