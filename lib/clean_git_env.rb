# frozen_string_literal: true

# The environment every spawn of `git` clears before running.
#
# #789 — a `-C <dir>`-scoped git call LOSES to an inherited GIT_DIR: with one
# set, `git -C x init` re-initialises $GIT_DIR (flipping core.bare when $GIT_DIR
# is a worktree gitdir) and `git -C x config` writes $GIT_DIR/config, which for a
# linked worktree is the SHARED repository config. Git hooks export GIT_DIR
# (man 5 githooks), so anything invoked from a hook inherits one — and the damage
# lands in a repository nobody was looking at.
#
# The GIT_CONFIG_* family rides along for completeness rather than for #789 —
# hooks do not export it — because any variable that can redirect a config write
# belongs in the set: GIT_CONFIG sends `git config` writes to an arbitrary file,
# and GIT_CONFIG_GLOBAL/SYSTEM/COUNT redirect or inject reads.
# GIT_CEILING_DIRECTORIES is deliberately absent: it steers repository discovery,
# which is already settled once GIT_DIR is nil.
#
# A nil value DELETES the key in the child process, restoring `-C` precedence.
#
# One home, because three spellings of this hash is how the second omission
# happened: #1057 fixed eight sites, and two days later a new spec shelled to git
# bare and nobody noticed (#1056). `spec/code_smells/git_spawns_clear_git_env_spec.rb`
# now fails on a bare git spawn, and it matches on this constant's name — so a
# fourth copy under another name would not satisfy it.
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
