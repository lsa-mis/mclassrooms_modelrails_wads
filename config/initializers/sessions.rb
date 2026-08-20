# Session lifecycle policy. One home for the knobs a fork tunes.
#
# touch_throttle: how stale last_active_at may get before a request refreshes
# it (keeps the write off the SQLite single-writer hot path).
Rails.application.config.x.session.idle_timeout = 30.days
Rails.application.config.x.session.absolute_timeout = 90.days
Rails.application.config.x.session.touch_throttle = 5.minutes

# Re-authentication ("confirm it's you") for sensitive account changes. When
# reauth_enabled is false, require_reauthentication! is a no-op (some
# single-tenant/internal-tool forks won't want the friction).
Rails.application.config.x.session.reauth_window = 15.minutes
Rails.application.config.x.session.reauth_enabled = true

# New-device sign-in alerts. Fingerprints are still RECORDED when this is off —
# the flag gates only the alert, so flipping it back on later keeps full device
# history. Off for internal tools where every teammate's laptop would fire one
# on day one.
Rails.application.config.x.session.new_device_notification = true
