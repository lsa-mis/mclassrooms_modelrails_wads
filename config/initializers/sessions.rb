# Session lifecycle policy. One home for the knobs a fork tunes.
#
# - idle_timeout:     signed out after this long with no activity
# - absolute_timeout: signed out this long after sign-in regardless of activity
# - touch_throttle:   how stale last_active_at may get before a request refreshes
#                     it (keeps the write off the SQLite single-writer hot path)
Rails.application.config.x.session.idle_timeout = 30.days
Rails.application.config.x.session.absolute_timeout = 90.days
Rails.application.config.x.session.touch_throttle = 5.minutes
