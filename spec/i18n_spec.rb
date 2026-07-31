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

  # Two further i18n-tasks checks are deliberately not gating the suite yet.
  #
  # `unused` (#522) reports ~140 keys orphaned by past refactors — the whole
  # workspaces.invitations.index.* block, for instance, outlived the route and
  # view it belonged to. Clearing those is its own change with its own review.
  #
  # `normalize` (#523) rewrites every locale file, and the dotted
  # activity.actions keys ("workspace.updated") read as nested paths to its
  # router — so normalizing relocates them out of activity.en.yml into the
  # catch-all, fragmenting the domain-split layout this project curates by
  # hand. Needs per-namespace write rules first.
  #
  # Run `bundle exec i18n-tasks unused` / `normalize` to see either.
end
