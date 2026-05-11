module Account
  module Preferences
    # Timezone beacon endpoint. Fires from the layout-level Stimulus
    # controller (timezone_beacon_controller) which reads
    # Intl.DateTimeFormat().resolvedOptions().timeZone on connect.
    #
    # Idempotency contract: the beacon writes only when the stored timezone
    # is blank, so an explicit user choice is never clobbered by the
    # browser's reading. The preferences-page Change action sets
    # `override=true` to bypass the guard.
    class TimezonesController < ApplicationController
      # TZInfo::Timezone.all_identifiers is the full IANA database (~598
      # entries) — what Intl.DateTimeFormat returns in the browser.
      # ActiveSupport::TimeZone.all is a curated subset (~152 zones) that
      # rejects valid IANA names like "America/Detroit" or
      # "America/Indiana/Indianapolis" — those would land 422 here.
      VALID_IANA_NAMES = TZInfo::Timezone.all_identifiers.to_set.freeze

      def update
        tz = params[:timezone].to_s
        return head :unprocessable_entity unless VALID_IANA_NAMES.include?(tz)

        preferences = Current.user.preferences || Current.user.create_preferences!
        override = params[:override].to_s == "true"

        if preferences.timezone.blank? || override
          preferences.update!(timezone: tz)
        end

        head :no_content
      end
    end
  end
end
