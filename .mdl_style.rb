all

# Translated from the prior .markdownlintrc (markdownlint-cli). Same MDxxx
# rule numbering, but mdl (Ruby, kramdown-based) and markdownlint-cli
# (Node) implement several rules with different default heuristics — MD002,
# MD007, and MD026 below were NOT disabled in .markdownlintrc but fire here
# on deliberate, pre-existing content (a template's intro HTML comment
# before its first heading, a natural "Need help?" heading, standard nested-
# list indentation) that markdownlint-cli's defaults already tolerate. Added
# for parity with the previous clean baseline, not because the content is
# wrong.
exclude_rule 'MD001'
exclude_rule 'MD002'
exclude_rule 'MD007'
exclude_rule 'MD013'
exclude_rule 'MD022'
exclude_rule 'MD024'
exclude_rule 'MD025'
exclude_rule 'MD026'
exclude_rule 'MD029'
exclude_rule 'MD032'
exclude_rule 'MD033'
exclude_rule 'MD036'
exclude_rule 'MD040'
exclude_rule 'MD041'
