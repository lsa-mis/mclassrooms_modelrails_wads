# Stdlib only, like ChangeLanes. See /docs/developer/getting-started (Gate 1).
module ProtectedBranchCheck
  BRANCHES = %w[next main].freeze

  Push = Data.define(:local_ref, :local_sha, :remote_ref, :remote_sha) do
    def branch = remote_ref.delete_prefix("refs/heads/")
    def protected? = remote_ref.start_with?("refs/heads/") && BRANCHES.include?(branch)
    def creates? = remote_sha.match?(/\A0+\z/)
    def deletes? = local_sha.match?(/\A0+\z/)
    def from_same_branch? = local_ref == remote_ref
    def local_name = local_ref.delete_prefix("refs/heads/")
  end

  def self.refusal(lines, remote: "origin", off: [])
    refused = lines.map(&:split).filter_map { |fields| Push.new(*fields) if fields.size == 4 }
      .select { |push| push.protected? && !push.creates? && !off.include?(push.branch) }
    refused.map { |push| message(push, remote) }.join("\n") unless refused.empty?
  end

  def self.message(push, remote)
    branch = push.branch
    return "#{remote}'s #{branch} is protected: GitHub refuses to delete it.\n" if push.deletes?

    steps = if push.from_same_branch?
      [ "git switch -c <branch>", "git branch -f #{branch} #{remote}/#{branch}", "git push -u #{remote} <branch>" ]
    else
      [ "git push -u #{remote} #{push.local_name}" ]
    end
    <<~TEXT
      #{remote}'s #{branch} only takes pull requests, so GitHub would refuse this push after every check had run.
      Push a branch of your own and open a pull request into #{branch}:
      #{[ *steps, "gh pr create --base #{branch}" ].map { |step| "  #{step}" }.join("\n")}
    TEXT
  end
  private_class_method :message
end
