# frozen_string_literal: true

# Git in a throwaway repository, for specs of scripts that read a branch's history.
module ScratchGit
  def scratch_git(repo, *args)
    system(CleanGitEnv::HASH, "git", "-C", repo.to_s, "-c", "user.email=t@example.com", "-c", "user.name=T", *args,
           out: File::NULL, err: File::NULL, exception: true)
  end
end

RSpec.configure do |config|
  config.include ScratchGit
end
