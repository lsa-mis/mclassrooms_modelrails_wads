# VOCABULARY_OVERRIDE=<yml> runs the suite as a renamed fork sees it (#1112);
# unset, it does nothing. Once per process: Vocabulary.tokens is memoized.
if ENV["VOCABULARY_OVERRIDE"].present?
  RSpec.configure do |config|
    config.before(:suite) do
      path = Rails.root.join(ENV["VOCABULARY_OVERRIDE"])

      unless path.exist?
        raise ArgumentError,
          "VOCABULARY_OVERRIDE=#{ENV['VOCABULARY_OVERRIDE']} names no file at #{path}. " \
          "A run that silently kept the template's nouns would prove nothing."
      end

      Vocabulary.reload!(override: path)

      # Loud, so the log answers "which vocabulary was this?" first.
      warn "[vocabulary] fork simulation active: #{path.basename} " \
           "(#{Vocabulary.tokens[:workspace]}/#{Vocabulary.tokens[:project]})"
    end
  end
end
