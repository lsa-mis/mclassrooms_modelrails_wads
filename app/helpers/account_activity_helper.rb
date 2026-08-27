# frozen_string_literal: true

module AccountActivityHelper
  # The label for one row of the recent-account-activity card.
  #
  # Metadata stays off the card as a rule. The OS on a new-device sign-in is
  # the exception (#832): "signed in from a new device" alone gives a user
  # nothing to recognise or disown, and the platform is what makes the row
  # actionable.
  #
  # The exception is sanctioned by the LOCALE, not by the metadata — an
  # `<action>_with_os` key has to exist for the OS to appear at all. A row
  # carrying an `os` alongside something that must not render, such as a
  # passkey's user-supplied nickname, falls through to the bare label with no
  # second guard to remember. Adding a metadata-naming label is therefore a
  # deliberate act, which is the property worth having here.
  #
  # The trailing humanized fallback covers a SECURITY_ACTIONS member shipped
  # without a label: readable text rather than "translation missing".
  def account_activity_label(entry)
    os = entry.metadata&.dig("os").presence
    bare = :"settings.sessions.activity.#{entry.action}"

    t("#{bare}#{"_with_os" if os}",
      os: os,
      default: [ bare, entry.action.delete_prefix("user.").humanize ])
  end

  # The exact moment behind a row's relative time, for the `title` on its
  # <time>. "About 5 hours ago" is the right default for scanning, but not
  # enough to decide whether an unfamiliar sign-in was yours.
  #
  # `title` is additive to the accessible name rather than a replacement:
  # accname consults `title` only as a last resort, for an element with no
  # text content. This <time> has content, so screen readers keep announcing
  # the relative text and the title is a sighted-hover affordance on top.
  #
  # UserPreferences#time_zone is the single owner of the unset-or-unrecognized
  # fallback rule — never re-derive it here.
  def account_activity_timestamp(entry)
    zone = Current.user.preferences&.time_zone || Time.zone
    l(entry.created_at.in_time_zone(zone), format: :account_activity)
  end
end
