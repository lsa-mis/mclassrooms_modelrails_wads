# frozen_string_literal: true

# House cops: the playbook's shape rules made executable, loaded by
# .rubocop.yml's `require:` on top of omakase's style config. One file per
# cop under cop/modelrails/. Every offense message says what broke, how to
# fix it, which pattern applies, and where to read more.
require "rubocop"

require_relative "cop/modelrails/model_concern_namespace"
require_relative "cop/modelrails/no_default_scope"
require_relative "cop/modelrails/no_sleep_in_system_specs"
require_relative "cop/modelrails/no_i18n_default"
require_relative "cop/modelrails/no_current_user_shim"
require_relative "cop/modelrails/stack_floor"
require_relative "cop/modelrails/restful_actions"
require_relative "cop/modelrails/no_ambient_current_in_models"
