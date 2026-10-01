# frozen_string_literal: true

# Cleared before every git spawn: a hook's GIT_DIR beats `git -C` (#789). One home,
# fenced by spec/code_smells/git_spawns_clear_git_env_spec.rb.
module CleanGitEnv
  HASH = {
    "GIT_DIR" => nil,
    "GIT_WORK_TREE" => nil,
    "GIT_INDEX_FILE" => nil,
    "GIT_COMMON_DIR" => nil,
    "GIT_OBJECT_DIRECTORY" => nil,
    "GIT_NAMESPACE" => nil,
    "GIT_CONFIG" => nil,
    "GIT_CONFIG_GLOBAL" => nil,
    "GIT_CONFIG_SYSTEM" => nil,
    "GIT_CONFIG_COUNT" => nil
  }.freeze
end
