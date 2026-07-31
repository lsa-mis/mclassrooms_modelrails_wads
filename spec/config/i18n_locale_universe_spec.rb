# frozen_string_literal: true

require "rails_helper"

# The locale universe has to be identical in every environment.
#
# It is not identical by default: `faker` is a development/test gem and ships
# ~350 locale files, so an unpinned `I18n.available_locales` is ~60 entries in
# test and exactly [:en] in production. Anything keyed off a user-supplied
# locale then behaves one way under test and raises `I18n::InvalidLocale` in
# production, because `enforce_available_locales!` runs before the backend and
# before any fallback. Pinning the list in config/application.rb is what makes
# the two agree.
#
# A fork adding a language registers it there — one obvious place — and these
# specs start guarding the new list automatically.
RSpec.describe "I18n locale universe" do
  it "is pinned to the application's own locales, not the gem-inflated set" do
    expect(I18n.available_locales).to eq([ :en ])
  end

  it "does not leak locales from development/test-only gems" do
    faker_locales = I18n.load_path.grep(/faker/).any?
    expect(faker_locales).to be(true), "expected faker's locale files on the load path in test"

    # …and yet they must not widen the universe the app will accept.
    expect(I18n.available_locales).not_to include(:ru, :fr, :ja)
  end

  # Everything this branch protects rests on one uncommented line in
  # config/environments/test.rb. Assert the outcome, not the setting, so it
  # survives Rails changing how the flag is wired — and so nobody can quietly
  # comment it out to unblock a red build.
  it "raises rather than resolving a missing key to placeholder text" do
    expect { I18n.t("definitely.not.a.real.key.anywhere") }
      .to raise_error(I18n::MissingTranslationData)
  end

  it "rejects a locale outside the pinned set, as production does" do
    expect { I18n.t("notifications.placeholder", locale: :fr) }
      .to raise_error(I18n::InvalidLocale)
  end
end
