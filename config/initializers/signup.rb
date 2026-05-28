valid_modes = %i[open invite_only]
unless valid_modes.include?(Rails.configuration.x.signup.mode)
  raise "Invalid SIGNUP_MODE: #{Rails.configuration.x.signup.mode.inspect}. " \
        "Must be one of: #{valid_modes.join(', ')}"
end

# Join-strategy allowlist: the instance ceiling on per-workspace join_policy.
# :invite is always permitted (it's the universal default); operators opt in
# to additional strategies via SIGNUP_PERMITTED_JOIN_STRATEGIES.
valid_strategies = %i[invite open_link]
unknown_strategies = Rails.configuration.x.signup.permitted_join_strategies - valid_strategies
if unknown_strategies.any?
  raise "Unknown SIGNUP_PERMITTED_JOIN_STRATEGIES: #{unknown_strategies.join(', ')}. " \
        "Must be a subset of: #{valid_strategies.join(', ')}"
end
unless Rails.configuration.x.signup.permitted_join_strategies.include?(:invite)
  raise "SIGNUP_PERMITTED_JOIN_STRATEGIES must include :invite (the universal default)"
end
