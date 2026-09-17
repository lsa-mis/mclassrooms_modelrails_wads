# The nouns a fork renames: two stored forms each, casing derived. Constant
# after boot, because the I18n hook reads it on every lookup that uses a noun.
# See /docs/developer/forking (Vocabulary).
module Vocabulary
  class InvalidVocabulary < StandardError; end

  NOUNS = %i[workspace project].freeze
  FORMS = %i[singular plural].freeze
  DEFAULTS_PATH = Rails.root.join("config/vocabulary.yml")
  OVERRIDE_PATH = Rails.root.join("config/vocabulary.local.yml")

  class << self
    def tokens
      @tokens ||= reload!
    end

    def reload!(defaults: DEFAULTS_PATH, override: OVERRIDE_PATH)
      nouns = read(defaults).deep_merge(read(override))
      @tokens = NOUNS.each_with_object({}) do |noun, tokens|
        forms = nouns.fetch(noun.to_s) { raise InvalidVocabulary, "#{defaults.basename}: no entry for #{noun}" }
        singular = forms["singular"]
        plural = forms["plural"]
        tokens[noun] = singular
        tokens[:"#{noun}s"] = plural
        tokens[:"#{noun.to_s.upcase_first}"] = singular.upcase_first
        tokens[:"#{noun.to_s.upcase_first}s"] = plural.upcase_first
      end.freeze
end

    private

    def read(path)
      return {} unless path.exist?

      data = YAML.safe_load_file(path) || {}
      raise InvalidVocabulary, "#{path.basename}: expected a mapping of nouns" unless data.is_a?(Hash)

      unknown = data.keys.map(&:to_s) - NOUNS.map(&:to_s)
      raise InvalidVocabulary, "#{path.basename}: unknown noun(s) #{unknown.join(', ')} — the template knows #{NOUNS.join(', ')}" if unknown.any?

      data.each do |noun_str, forms|
        noun = noun_str.to_sym
        FORMS.each do |form|
          value = forms.is_a?(Hash) ? forms[form.to_s] : nil
          unless value.is_a?(String) && !value.strip.empty?
            raise InvalidVocabulary, "#{path.basename}: #{noun} needs a non-empty #{form} (got #{forms.inspect})"
          end
        end
      end

      data
    end
  end
end
