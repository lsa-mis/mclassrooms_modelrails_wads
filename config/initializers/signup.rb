valid_modes = %i[open invite_only]
unless valid_modes.include?(Rails.configuration.x.signup.mode)
  raise "Invalid SIGNUP_MODE: #{Rails.configuration.x.signup.mode.inspect}. " \
        "Must be one of: #{valid_modes.join(', ')}"
end
