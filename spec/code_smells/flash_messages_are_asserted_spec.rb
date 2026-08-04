require "rails_helper"
require "yaml"

# Six locale keys rendered `translation missing` to real users while their
# request specs passed, because those specs asserted `redirect_to(...)` and
# never the message (#521). A redirect-only assertion walks the path but proves
# nothing about what the user reads, so copy can be wrong, empty, or the wrong
# key entirely and stay green.
#
# The project's other two i18n gates do not close this:
#   * `raise_on_missing_translations` fires only when a spec walks the path AND
#     the call site carries no inline `default:`.
#   * `i18n-tasks missing` covers EXISTENCE.
# Neither covers *selection of the right key* — which is the whole game when two
# branches redirect to the same place. Adding these assertions immediately found
# one: the already-accepted invitation path is caught by `find_valid_invitation`
# (`expired_or_used`), not the `NotAcceptable` rescue (`acceptance_failed`). Both
# redirect to root, so only the message tells them apart.
RSpec.describe "Flash messages are asserted, not just redirects" do
  # Every controller flash no spec asserts today. This is a burn-down list, not
  # configuration: delete an entry as its assertion lands (#526). New arrivals
  # fail the first example rather than being added here.
  UNASSERTED_FLASHES = [
    "clientside.area.resource_unavailable",
    "clientside.area.unavailable",
    "clientside.invitations.disabled",
    "clientside.settings.saved",
    "email_verification_resends.create.no_email_auth",
    "email_verification_resends.create.rate_limited",
    "email_verification_resends.create.success",
    "email_verifications.show.invalid_or_expired",
    "magic_links.create.rate_limited",
    "notifications.destroy.success",
    "omniauth_callbacks.create.already_linked",
    "omniauth_callbacks.create.collision_other_user",
    "omniauth_callbacks.create.linked",
    "omniauth_callbacks.create.pending",
    "omniauth_callbacks.create.pending_in_progress",
    "omniauth_callbacks.create.pending_resent",
    "omniauth_callbacks.create.unverified_email_pending",
    "onboarding.projects.create.success",
    "onboarding.teams.create.sent",
    "onboarding.workspaces.create.success",
    "onboardings.update.complete",
    "project_tools.disabled",
    "project_tools.settings.saved",
    "sessions.create.failure",
    "sessions.create.oauth_failure",
    "sessions.create.rate_limited",
    "sessions.destroy.success",
    "settings.avatars.destroy.success",
    "settings.avatars.source_unavailable",
    "settings.avatars.update.rate_limited",
    "settings.avatars.update.success",
    "settings.connected_accounts.destroy.success",
    "settings.connected_accounts.resend_verification.already_verified",
    "settings.connected_accounts.resend_verification.rate_limited",
    "settings.connected_accounts.resend_verification.resent",
    "settings.connected_accounts.verify.invalid_or_expired",
    "settings.connected_accounts.verify.success",
    "settings.passkeys.destroy.success",
    "settings.passwords.create.already_has_password",
    "settings.passwords.create.success",
    "settings.passwords.destroy.success",
    "settings.passwords.update.success",
    "settings.profiles.update.verification_sent",
    "settings.theme_preferences.update.invalid_theme",
    "settings.theme_preferences.update.success",
    "workspaces.brandings.source_unavailable",
    "workspaces.create.success",
    "workspaces.destroy.success",
    "workspaces.invitations.create.magic_link_created",
    "workspaces.invitations.create.sent",
    "workspaces.invitations.destroy.revoked",
    "workspaces.invitations.resend.magic_link_refreshed",
    "workspaces.invitations.resend.rate_limited",
    "workspaces.join_links.create.rotated",
    "workspaces.join_links.destroy.revoked",
    "workspaces.joins.create.already_member",
    "workspaces.joins.create.joined",
    "workspaces.joins.create.register_first",
    "workspaces.members.destroy.cannot_deactivate_last_owner",
    "workspaces.members.destroy.cannot_leave_last_owner",
    "workspaces.members.reactivate.reactivated",
    "workspaces.members.transfer_ownership.transferred",
    "workspaces.members.update.success",
    "workspaces.projects.create.success",
    "workspaces.projects.invitations.create.success",
    "workspaces.projects.memberships.create.success",
    "workspaces.projects.memberships.destroy.removed",
    "workspaces.projects.memberships.toggle_pin.toggled",
    "workspaces.projects.memberships.update.invalid_role",
    "workspaces.projects.memberships.update.role_updated",
    "workspaces.projects.not_found",
    "workspaces.projects.resources.create.success",
    "workspaces.projects.resources.destroy.success",
    "workspaces.projects.resources.invalid_type",
    "workspaces.projects.resources.update.success",
    "workspaces.projects.update.success",
    "workspaces.settings.update.success",
    "workspaces.update.success"

    # No MClassrooms fork entries. The twelve admin flashes parked here when
    # this gate arrived are all asserted now — see spec/requests/admin/. If a
    # fork block is ever needed again, put it at the END of the array:
    # upstream's own burn-down edits land alphabetically mid-array, so a
    # trailing block keeps merging cleanly instead of colliding every sync.
  ].freeze

  def locale_values
    Dir.glob(Rails.root.join("config/locales/en/**/*.yml")).each_with_object({}) do |file, values|
      data = YAML.safe_load_file(file, aliases: true)
      next unless data.is_a?(Hash)

      flatten_locale(data, "", values)
    rescue Psych::Exception
      next
    end
  end

  def flatten_locale(hash, prefix, values)
    hash.each do |key, value|
      path = prefix.empty? ? key : "#{prefix}.#{key}"
      if value.is_a?(Hash)
        flatten_locale(value, path, values)
      else
        values[path.sub(/\Aen\./, "")] = value.to_s
      end
    end
  end

  # Resolves lazy `t(".key")` against its controller and action, which is how
  # nearly every flash in this app is written.
  def controller_flash_keys
    Dir.glob(Rails.root.join("app/controllers/**/*.rb")).flat_map do |path|
      controller = path.to_s.split("app/controllers/").last.sub("_controller.rb", "")
      action = nil

      File.readlines(path).filter_map do |line|
        action = Regexp.last_match(1) if line =~ /\A\s*def\s+([a-z_]+)/
        next unless line =~ /(?:notice|alert):\s*(.+)/

        expression = Regexp.last_match(1)
        if expression =~ /t\(\s*"\.([a-z_.]+)"/
          "#{controller.tr('/', '.')}.#{action}.#{Regexp.last_match(1)}"
        elsif expression =~ /t\(\s*"([a-z_.]+)"/
          Regexp.last_match(1)
        end
      end
    end.uniq
  end

  # Asserted by key (when the point is which key was selected) or by its English
  # text (when the point is that a real sentence reached the user). The length
  # guard keeps a short shared word like "Saved." from matching incidentally.
  def asserted?(key, values, specs)
    return true if specs.include?(key)

    text = values[key]
    text.present? && text.length > 8 && specs.include?(text)
  end

  let(:values) { locale_values }

  # Excludes THIS file: the burn-down list below names all 80 keys as string
  # literals, so scanning it would report every one of them as asserted and the
  # guard would pass on an empty promise.
  let(:specs) do
    Dir.glob(Rails.root.join("spec/**/*_spec.rb"))
      .reject { |f| f == __FILE__ }
      .map { |f| File.read(f) }.join("\n")
  end

  it "asserts every flash a controller sets, or tracks it on the burn-down list" do
    unasserted = controller_flash_keys.reject { |key| asserted?(key, values, specs) }
    new_arrivals = unasserted - UNASSERTED_FLASHES

    expect(new_arrivals).to be_empty,
      "these controller flashes are asserted by no spec:\n  #{new_arrivals.join("\n  ")}\n\n" \
      "Assert the message, not just the redirect — `expect(flash[:notice]).to eq(I18n.t(\"...\"))` " \
      "in the request spec for that action. A redirect-only assertion cannot tell a wrong key " \
      "from a right one."
  end

  it "keeps the burn-down list honest — no entry that is now asserted" do
    stale = UNASSERTED_FLASHES.select { |key| asserted?(key, values, specs) }

    expect(stale).to be_empty,
      "these are asserted now — delete them from UNASSERTED_FLASHES so the list keeps " \
      "meaning something:\n  #{stale.join("\n  ")}"
  end
end
