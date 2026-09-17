# The app's one I18n backend customization: a fork's nouns
# (config/vocabulary.local.yml) reach every translation without call sites
# passing them. Prepended on `translate`, not `interpolate`, and only for
# strings that use a noun token — the gem skips interpolation on value-less
# calls, and a string keeping %{count} for client-side JS must stay that way.
# The reasoning and its costs: /docs/developer/i18n (Vocabulary), #1109, #1111.
module VocabularyInterpolation
  def translate(locale, key, options = I18n::EMPTY_HASH)
    # A literal-default lookup arrives with a nil key: nothing to scan.
    return super if key.nil?
    return super unless uses_vocabulary?(lookup(locale, key, options[:scope], options))

    super(locale, key, Vocabulary.tokens.merge(options))
  end

  private

  def uses_vocabulary?(resolved)
    case resolved
    when String then resolved.match?(vocabulary_token_pattern)
    when Hash then resolved.values.any? { |value| uses_vocabulary?(value) }
    when Array then resolved.any? { |value| uses_vocabulary?(value) }
    else false
    end
  end

  # Built on first use: Vocabulary autoloads after initializers have run.
  def vocabulary_token_pattern
    @vocabulary_token_pattern ||= /%\{(#{Vocabulary.tokens.keys.join("|")})\}/
  end
end

I18n::Backend::Simple.prepend(VocabularyInterpolation)
