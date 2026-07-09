# frozen_string_literal: true

# Shared Bullet safelists for development + test.
#
# These encode intentional preload / delivery-layer trade-offs that hold in BOTH
# environments (the app code is identical), so they live here instead of being
# duplicated per env file. They drifted once: dev.rb carried only 2 of them while
# test.rb had the full set, so notifications-index false positives fired in dev
# (Bullet.alert popup) but never in test (Bullet.raise) — invisible to the suite.
# One source removes that whole class of drift. Each env file keeps its own
# enable / display / raise config and calls `BulletSafelists.apply` after
# `Bullet.enable = true`.
#
# Loaded via `require_relative` from the env configs, which run before Zeitwerk
# autoloading is active — same pattern as lib/codespaces.rb.
module BulletSafelists
  module_function

  def apply
    apply_unused_eager_loading
    apply_n_plus_one
  end

  # --- Unused eager loading -------------------------------------------------

  def apply_unused_eager_loading
    # ActiveStorage touches attachment records via includes(:record) for a bulk
    # SQL touch (touch_attachment_records); the objects are never accessed in Ruby,
    # so Bullet's "avoidable eager loading" is a framework false positive.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "ActiveStorage::Attachment", association: :record)

    # The notifications index eager-loads `event.record` for every row
    # (`includes(:recipient, event: :record)`) because ~all notifier subtypes'
    # `#message` interpolate `event.record.<attr>`. SignInFromNewDeviceNotifier is
    # the lone exception — its `#message` reads only `event.params` — so when it's
    # the only subtype on the page the `:record` include is unused. Keep the preload
    # (N+1 guard for the common case); accept the false positive for a device-only page.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "SignInFromNewDeviceNotifier", association: :record)

    # The workspace sidebar switcher preloads `memberships: [:role, { user: :avatar_attachment }]`
    # so `workspace_icon_for` can fall back to the personal-workspace owner's avatar
    # without N+1ing. The fallback is conditional (skipped when a workspace has its own
    # logo, or under the :none sidebar posture), leaving legs of the chain "unused" on
    # those rows. Also covers Workspace#owners' loaded?-aware short-circuit on the
    # workspaces index. Intentionally pessimistic — cheaper than an N+1 on the rows that
    # DO need it — so safelist every leg.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :user)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :role)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "User", association: :avatar_attachment)

    # WorkspacesController#index queries memberships first then joins+preloads workspace
    # to sort by memberships.last_accessed_at; Bullet reads the includes-side preload as
    # redundant against the join alias, but the view needs the preloaded workspace per
    # row to render name + icon without an N+1.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Membership", association: :workspace)

    # RoomSearch#results (Find a Room, phase 3 Task 2) preloads the associations the
    # index CARDS need per room — building/floor labels, characteristic chips, gallery
    # thumbnail — so the phase-4 view renders a page of rooms without N+1ing. The
    # RoomSearch unit spec exercises filtering/sorting only (no view render), so it
    # never dereferences these; safelisted rather than dropped so the real controller
    # path keeps the guard.
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :building)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :floor)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :room_characteristics)
    Bullet.add_safelist(type: :unused_eager_loading, class_name: "Room", association: :gallery_images)
  end

  # --- N+1 query ------------------------------------------------------------

  def apply_n_plus_one
    # DELIVERY-LAYER ONLY: Noticed v2's EventJob iterates `event.notifications.each`
    # and reads each notification's `recipient` (for the deliver_by :email lambda's
    # recipient_pref check + the Email params hash). The gem exposes no hook to
    # eager-load `:recipient` on that relation. Only the delivery-iteration path is
    # whitelisted — a resolver-layer N+1 (e.g. WorkspaceMemberAddedNotifier#recipients
    # eager-loads :user explicitly) will still trip Bullet correctly.
    Bullet.add_safelist(type: :n_plus_one_query, class_name: "WorkspaceMemberAddedNotifier::Notification", association: :recipient)
    Bullet.add_safelist(type: :n_plus_one_query, class_name: "WorkspaceCapacityApproachingNotifier::Notification", association: :recipient)

    # The notifications index renders a mixed page of notifier subtypes whose `#message`
    # traverses deep off the polymorphic `event.record` — Membership's user/workspace
    # (WorkspaceMemberAdded/RoleChanged) and Invitation's accepted_by/invitable
    # (WorkspaceInvitation*). Rails' polymorphic `includes(event: :record)` can't
    # transitively eager-load these without a per-subtype preload pipeline; accepting
    # the N+1 on this page is the trade-off.
    Bullet.add_safelist(type: :n_plus_one_query, class_name: "Membership", association: :user)
    Bullet.add_safelist(type: :n_plus_one_query, class_name: "Membership", association: :workspace)
    Bullet.add_safelist(type: :n_plus_one_query, class_name: "Invitation", association: :accepted_by)
    Bullet.add_safelist(type: :n_plus_one_query, class_name: "Invitation", association: :invitable)
  end
end
