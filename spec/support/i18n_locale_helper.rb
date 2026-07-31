# frozen_string_literal: true

# Registers an extra locale for the duration of a block.
#
# `I18n.translate` calls `enforce_available_locales!` BEFORE it reaches the
# backend, so passing `locale:` for anything outside `I18n.available_locales`
# raises `I18n::InvalidLocale` — fallbacks never get a chance to run. Specs
# that exercise multi-locale behaviour therefore have to register the locale
# the way a fork would, rather than assuming any string works.
module I18nLocaleHelper
  def with_available_locale(locale, translations = {})
    original = I18n.available_locales
    I18n.available_locales = (original + [ locale.to_sym ]).uniq
    I18n.backend.store_translations(locale.to_sym, translations) if translations.any?
    yield
  ensure
    I18n.available_locales = original
  end
end

RSpec.configure do |config|
  config.include I18nLocaleHelper
end
