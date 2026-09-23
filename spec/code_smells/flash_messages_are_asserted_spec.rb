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
  # fail the first example rather than being added here — the two exceptions
  # were flashes that had always existed and only became visible when the scan
  # learned the other two spellings, so they were debt already, not new.
  unasserted_flashes = [
    "clientside.area.resource_unavailable",
    "clientside.area.unavailable",
    "clientside.invitations.disabled",
    "clientside.invitations.invalid",
    "clientside.settings.saved",
    "email_verification_resends.create.no_email_auth",
    "email_verification_resends.create.rate_limited",
    "email_verification_resends.create.success",
    "magic_links.create.rate_limited",
    "omniauth_callbacks.create.already_linked",
    "omniauth_callbacks.create.collision_other_user",
    "omniauth_callbacks.create.linked",
    "omniauth_callbacks.create.pending",
    "omniauth_callbacks.create.pending_in_progress",
    "omniauth_callbacks.create.pending_resent",
    "omniauth_callbacks.create.unverified_email_pending",
    "onboarding.projects.create.success",
    "onboarding.teams.create.no_emails",
    "onboarding.teams.create.sent",
    "onboarding.workspaces.create.success",
    "onboardings.update.complete",
    "project_tools.disabled",
    "project_tools.settings.saved",
    "sessions.create.failure",
    "sessions.create.oauth_failure",
    "sessions.create.rate_limited",
    "sessions.destroy.success",
    "settings.connected_accounts.destroy.success",
    "settings.connected_accounts.verification_resends.create.already_verified",
    "settings.connected_accounts.verification_resends.create.rate_limited",
    "settings.connected_accounts.verification_resends.create.resent",
    "settings.reauthentications.rate_limited",
    "settings.passwords.create.already_has_password",
    "settings.profiles.update.verification_sent",
    "workspaces.invitations.create.magic_link_created",
    "workspaces.invitations.resends.create.rate_limited",
    "workspaces.join_links.create.rotated",
    "workspaces.join_links.destroy.revoked",
    "workspaces.joins.create.already_member",
    "workspaces.joins.create.joined",
    "workspaces.joins.create.register_first",
    "workspaces.projects.invitations.create.success",
    "workspaces.projects.resources.destroy.success",
    "workspaces.projects.resources.update.success",
    "workspaces.settings.update.success"

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

        # Three spellings, because reading only the `notice:` kwarg made a live
        # flash look like a fossil: the bulk-invite message is built as a local
        # (`notice = t(...)`) and handed to redirect_to on the next line.
        expression =
          if line =~ /(?:notice|alert):\s*(.+)/
            Regexp.last_match(1)
          elsif line =~ /(?:flash(?:\.now)?\[:(?:notice|alert)\]|\b(?:notice|alert))\s*=(?!=)\s*(.+)/
            Regexp.last_match(1)
          end
        next unless expression
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
  #
  # Key matching is boundary-aware, not a bare substring: a plain `include?`
  # let a namespaced key falsely "assert" an unrelated shorter one — a spec
  # asserting operations.workspaces.create.success made the burn-down's
  # separate workspaces.create.success (the tenant's own create flash) read
  # as newly-asserted, because the shorter key is a dotted SUFFIX of the
  # longer one. Neither a `.` nor a word char may sit on either side of the
  # match.
  def asserted?(key, values, specs)
    return true if specs.match?(/(?<![\w.])#{Regexp.escape(key)}(?![\w.])/)

    text = values[key]
    text.present? && text.length > 8 && specs.include?(text)
  end

  let(:values) { locale_values }

  # Excludes THIS file: the burn-down list below names every one of these keys as string
  # literals, so scanning it would report every one of them as asserted and the
  # guard would pass on an empty promise.
  let(:specs) do
    Dir.glob(Rails.root.join("spec/**/*_spec.rb"))
      .reject { |f| f == __FILE__ }
      .map { |f| File.read(f) }.join("\n")
  end

  it "asserts every flash a controller sets, or tracks it on the burn-down list" do
    unasserted = controller_flash_keys.reject { |key| asserted?(key, values, specs) }
    new_arrivals = unasserted - unasserted_flashes

    expect(new_arrivals).to be_empty,
      "these controller flashes are asserted by no spec:\n  #{new_arrivals.join("\n  ")}\n\n" \
      "Assert the message, not just the redirect — `expect(flash[:notice]).to eq(I18n.t(\"...\"))` " \
      "in the request spec for that action. A redirect-only assertion cannot tell a wrong key " \
      "from a right one."
  end

  # The other direction of the same rot. An entry stops describing the code
  # either because the assertion landed (the example below) or because the
  # flash itself moved, was renamed, or was deleted — and a key no controller
  # sets any more is a line of debt this app does not owe (#526).
  it "keeps the burn-down list honest — no entry that names no flash" do
    live = controller_flash_keys
    fossils = unasserted_flashes.reject { |key| live.include?(key) }

    expect(fossils).to be_empty,
      "no controller sets these any more — the flash was renamed, moved, or removed, " \
      "so the entry now inflates the debt instead of recording it. Delete them:\n  " \
      "#{fossils.join("\n  ")}"
  end

  it "keeps the burn-down list honest — no entry that is now asserted" do
    stale = unasserted_flashes.select { |key| asserted?(key, values, specs) }

    expect(stale).to be_empty,
      "these are asserted now — delete them from unasserted_flashes so the list keeps " \
      "meaning something:\n  #{stale.join("\n  ")}"
  end
end
