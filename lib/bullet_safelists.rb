# frozen_string_literal: true

# Shared by development and test, loaded by require_relative before Zeitwerk is active. Each entry's
# trade-off: /docs/developer/testing (Bullet safelists live in one file).
module BulletSafelists
  module_function

  def apply
    apply_unused_eager_loading
    apply_n_plus_one
  end

  # --- Unused eager loading -------------------------------------------------

  def apply_unused_eager_loading
    # Framework false positive: ActiveStorage's bulk touch includes :record but never reads it.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "ActiveStorage::Attachment", association: :record)

    # The notifications index preloads event.record for every subtype; this one's message never reads it.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "SignInFromNewDeviceNotifier", association: :record)

    # Members index: unused on pages that render no invitation rows (#124/#125).
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Invitation", association: :role)

    # Sidebar switcher's owner-avatar fallback: conditional per row, so any leg can go unused.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :user)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :role)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "User", association: :avatar_attachment)

    # Workspaces index: Bullet misreads this preload as redundant against the join it sorts by.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :workspace)

    # RoomSearch#results (Find a Room, phase 3 Tasks 2 + 5) preloads the associations
    # the index ROWS need per room — building/floor labels, unit display name,
    # characteristic chips, gallery thumbnail — so the view renders a page of rooms
    # without N+1ing. The RoomSearch unit spec exercises filtering/sorting only (no
    # view render), so it never dereferences these; safelisted rather than dropped
    # so the real controller path keeps the guard.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :building)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :floor)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :unit)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :room_characteristics)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :gallery)

    # The thumbnail chain (RoomPresenter#thumbnail / #thumbnail_variant)
    # short-circuits — flat render, then bare panorama, then gallery — so the
    # later legs WILL be unused on any row that resolves early, and the
    # RoomSearch unit spec never renders at all (the rationale above).
    # Verified needed under the explicit `attachment: :blob` preloads:
    # removing them raises `Room => [:flat_panorama_attachment,
    # :panorama_attachment]` in the unit spec and on short-circuiting pages.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :flat_panorama_attachment)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :panorama_attachment)
    # The NESTED legs of the same short-circuit: a room with a flat panorama
    # AND gallery assets preloads `gallery: { image_attachment: :blob }` on
    # the index, but the chain resolves before touching any of it — so the
    # MediaAsset rows' image_attachment AND those attachments' blob both
    # read as unused. Missing these entries failed five rooms/show system
    # specs: sign-in lands on /find-a-room, and the raise surfaces
    # OUT-OF-CHANNEL via Bullet::Rack in the Capybara server. Request specs
    # can NOT catch this pair — the RSpec-hook example window is already
    # open, so Bullet::Rack skips its per-request window — the system suite
    # is the guard (spec/system/rooms/show_spec.rb).
    #
    # Breadth caveat: the Attachment→blob entry is app-wide (Bullet safelists
    # cannot scope to an owner), so it also masks any FUTURE genuinely-unused
    # `attachment: :blob` preload. The "never with_attached_X" rule above is
    # what keeps that risk small.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "MediaAsset", association: :image_attachment)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "ActiveStorage::Attachment", association: :blob)
  end

  # --- N+1 query ------------------------------------------------------------

  def apply_n_plus_one
    # Empty on purpose (#1054): a safelist is global and would hide a real N+1 on every other page.
    # The notifications index uses ApplicationNotifier.preload_records instead.
  end
end
