# Runs the suite as a renamed fork sees it.
#
# The vocabulary seam promises that a fork setting config/vocabulary.local.yml
# to its own nouns keeps this suite green. The template can only assert that
# indirectly: Gate C (spec/code_smells/spec_copy_assertions_use_i18n_spec.rb)
# forbids literal-noun copy assertions in the shapes it knows, and the seam's
# own review found ten assertions in shapes it does not — `eq`, `include`,
# `scan`, a guard counting a literal word — by actually running specs under a
# swapped override. That probe was a scratch file, so the next such assertion
# would land unnoticed until a real fork's suite went red (#1112).
#
# VOCABULARY_OVERRIDE=spec/fixtures/vocabulary.course.yml adopts a fixture
# vocabulary for the whole run without touching the tree. Unset, this file
# does nothing at all — the default lane is unaffected.
#
# before(:suite), not before(:each): Vocabulary.tokens is memoized and the I18n
# hook reads it on every lookup, so one reload at the top of the process is
# both sufficient and what a real fork's boot actually looks like. Under
# parallel_tests each worker is its own process and runs this itself.
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

      # Loud on purpose: a failure in this lane reads as an ordinary failure
      # otherwise, and the first question — "which vocabulary was this?" —
      # should already be answered at the top of the log.
      warn "[vocabulary] fork simulation active: #{path.basename} " \
           "(#{Vocabulary.tokens[:workspace]}/#{Vocabulary.tokens[:project]})"
    end
  end
end
