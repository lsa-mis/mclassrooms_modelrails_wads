# frozen_string_literal: true

require "i18n/tasks"

# Static counterpart to `config.i18n.raise_on_missing_translations` (see
# config/environments/test.rb): that catches a bad key only on a code path a
# spec actually exercises, this catches it repo-wide without executing anything.
# Runs as a normal spec so CI and the Lefthook pre-push hook both pick it up
# with no separate step to keep in sync.
RSpec.describe I18n do
  let(:i18n) { I18n::Tasks::BaseTask.new }

  it "does not have missing keys" do
    missing_keys = i18n.missing_keys
    expect(missing_keys).to be_empty,
      "Missing #{missing_keys.leaves.count} i18n keys, run `bundle exec i18n-tasks missing` to show them"
  end

  it "does not have inconsistent interpolations" do
    inconsistent = i18n.inconsistent_interpolations
    error_message = "#{inconsistent.leaves.count} i18n keys have inconsistent interpolations.\n" \
                    "Run `bundle exec i18n-tasks check-consistent-interpolations` to show them"
    expect(inconsistent).to be_empty, error_message
  end

  it "has no unused keys (#522 — 120 orphans were cleared when this gate landed)" do
    unused = i18n.unused_keys
    expect(unused).to be_empty,
      "#{unused.leaves.count} unused i18n keys — delete them (`bundle exec " \
      "i18n-tasks unused` to list), or add to ignore_unused in " \
      "config/i18n-tasks.yml with a reason if the consumer is dynamic or " \
      "lives in a scanner-excluded path (see the modals.* entry — deleting " \
      "those 'unused' keys broke 32 system specs)."
  end

  # `check-normalized` deliberately does NOT gate (#523, decided 2026-08-15
  # after trying it): i18n-tasks' writer strips hand-written comments —
  # including brand.en.yml's fork-seam header — and rewrites the YAML quoting
  # that two of bin/fork's byte-exact substitution tokens ("ModelRails and
  # support@example.com) match on; the rename-targets invariant caught the
  # breakage. There is no per-file opt-out. The per-namespace write router in
  # config/i18n-tasks.yml stays: it places `add-missing` keys in the correct
  # domain file, which was the half of normalize this layout actually needed.
end

# #911: keys under `activity.actions` were written flat and dotted
# ("membership.created:"). I18n's nested lookup splits the requested key on "."
# and walks the hash segment by segment, so a flat dotted key is unreachable —
# and the renderer's `default:` turned every miss into a humanized column value
# with nothing raising. i18n-tasks cannot see this: it flattens nested keys to
# the same dotted form, so both shapes look identical to the gates above.
RSpec.describe "activity.actions locale shape" do
  it "nests every key, because a dot inside a key never resolves" do
    dotted = []
    walk = lambda do |node, path|
      node.each do |key, value|
        dotted << (path + [ key ]).join(".") if key.to_s.include?(".")
        walk.call(value, path + [ key ]) if value.is_a?(Hash)
      end
    end
    walk.call(I18n.t("activity.actions"), [])

    expect(dotted).to be_empty,
      "Flat dotted keys under activity.actions never resolve (#911): #{dotted.join(', ')}"
  end
end
