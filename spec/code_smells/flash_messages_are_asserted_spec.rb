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

        # Three spellings, including a `notice = t(...)` local handed to redirect_to.
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

  # By key or by English text over 8 characters, so "Saved." can't match by chance. Boundary-aware:
  # asserting operations.workspaces.create.success must not count for its suffix workspaces.create.success.
  def asserted?(key, values, specs)
    return true if specs.match?(/(?<![\w.])#{Regexp.escape(key)}(?![\w.])/)

    text = values[key]
    text.present? && text.length > 8 && specs.include?(text)
  end

  let(:values) { locale_values }

  # Skips this file, whose comments name keys as examples.
  let(:specs) do
    Dir.glob(Rails.root.join("spec/**/*_spec.rb"))
      .reject { |f| f == __FILE__ }
      .map { |f| File.read(f) }.join("\n")
  end

  it "asserts every flash a controller sets" do
    unasserted = controller_flash_keys.reject { |key| asserted?(key, values, specs) }

    expect(unasserted).to be_empty,
      "these controller flashes are asserted by no spec:\n  #{unasserted.join("\n  ")}\n\n" \
      "Assert the message, not just the redirect — `expect(flash[:notice]).to eq(I18n.t(\"...\"))` " \
      "in the request spec for that action. A redirect-only assertion cannot tell a wrong key " \
      "from a right one."
  end
end
