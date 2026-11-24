require_relative "../../lib/protected_branch_check"

RSpec.describe ProtectedBranchCheck do
  let(:zero) { "0" * 40 }
  let(:old) { "a" * 40 }
  let(:new) { "b" * 40 }

  def refusal(*lines, **options) = described_class.refusal(lines, **options)

  describe "an existing protected branch" do
    it "refuses a push of local next to origin's next, with the way to a pull request" do
      message = refusal("refs/heads/next #{new} refs/heads/next #{old}")

      expect(message).to include("origin's next only takes pull requests")
      expect(message.lines.map(&:strip)).to include(
        "git switch -c <branch>",
        "git branch -f next origin/next",
        "git push -u origin <branch>",
        "gh pr create --base next"
      )
    end

    it "refuses main the same way, adapted for main" do
      message = refusal("refs/heads/main #{new} refs/heads/main #{old}")

      expect(message.lines.map(&:strip)).to include("git branch -f main origin/main", "gh pr create --base main")
    end

    it "names the remote the push went to" do
      expect(refusal("refs/heads/next #{new} refs/heads/next #{old}", remote: "fork")).to include(
        "fork's next", "git branch -f next fork/next", "git push -u fork <branch>"
      )
    end

    it "leaves the local branch alone when the commits came from another one" do
      message = refusal("refs/heads/hotfix/x #{new} refs/heads/main #{old}")

      expect(message.lines.map(&:strip)).to include("git push -u origin hotfix/x", "gh pr create --base main")
      expect(message).not_to include("git branch -f", "git switch -c")
    end

    it "refuses deleting it, without a recovery to follow" do
      message = refusal("(delete) #{zero} refs/heads/next #{old}")

      expect(message).to include("origin's next is protected")
      expect(message).not_to include("gh pr create")
    end

    it "refuses only the protected line of a push that carries several" do
      message = refusal("refs/heads/work #{new} refs/heads/work #{old}", "refs/heads/next #{new} refs/heads/next #{old}")

      expect(message).to include("--base next")
      expect(message).not_to include("work")
    end
  end

  describe "pushes it lets through" do
    it "allows creating next on a brand-new repository, as bin/fork's first push does" do
      expect(refusal("refs/heads/next #{new} refs/heads/next #{zero}")).to be_nil
    end

    it "reads a SHA-256 repository's zero id as new too" do
      expect(refusal("refs/heads/next #{"b" * 64} refs/heads/next #{"0" * 64}")).to be_nil
    end

    it "allows a feature branch, new or existing" do
      expect(refusal("refs/heads/work #{new} refs/heads/work #{zero}", "refs/heads/work #{new} refs/heads/work #{old}")).to be_nil
    end

    it "allows the branches bin/release and bin/sync create" do
      %w[changelog/2026.11.14 release/2026.11.14 merge-back/2026.11.14 sync/template-2026.11.14].each do |branch|
        expect(refusal("refs/heads/#{branch} #{new} refs/heads/#{branch} #{zero}")).to be_nil
      end
    end

    it "allows a branch whose name only starts like a protected one" do
      expect(refusal("refs/heads/next-step #{new} refs/heads/next-step #{old}")).to be_nil
    end

    it "allows deleting a feature branch" do
      expect(refusal("(delete) #{zero} refs/heads/work #{old}")).to be_nil
    end

    it "allows tags, including one named like a protected branch" do
      expect(refusal("refs/tags/v2026.11.14 #{new} refs/tags/v2026.11.14 #{zero}", "refs/tags/next #{new} refs/tags/next #{old}")).to be_nil
    end

    it "allows a branch named in off, for bin/fork's push to an unprotected fork and the emergency hotfix" do
      expect(refusal("refs/heads/next #{new} refs/heads/next #{old}", off: [ "next" ])).to be_nil
      expect(refusal("refs/heads/hotfix/x #{new} refs/heads/main #{old}", off: [ "main" ])).to be_nil
    end

    it "keeps refusing the branches off doesn't name" do
      expect(refusal("refs/heads/main #{new} refs/heads/main #{old}", off: [ "next" ])).to include("--base main")
    end

    it "allows an empty push" do
      expect(refusal).to be_nil
    end
  end
end
