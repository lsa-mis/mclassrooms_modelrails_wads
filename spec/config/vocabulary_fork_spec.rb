require "rails_helper"
require "tmpdir"

# What a fork gets: its override applied, the template's real keys render in
# its words, including the first-run wizard that the real Event fork shipped
# in the wrong word. Restores the defaults after, so no other example sees them.
RSpec.describe "A fork's vocabulary", type: :config do
  around do |example|
    Dir.mktmpdir do |dir|
      override = Pathname.new(dir).join("vocabulary.local.yml")
      override.write(%(workspace: { singular: "course", plural: "courses" }\nproject: { singular: "team", plural: "teams" }\n))
      Vocabulary.reload!(override: override)
      example.run
    ensure
      Vocabulary.reload!
    end
  end

  it "names the first-run wizard's step in the fork's words" do
    expect(I18n.t("onboarding.workspaces.new.title")).to eq("Name your course")
  end

  it "pluralizes in the fork's words" do
    expect(I18n.t("workspaces.sidebar.projects")).to eq("Teams")
  end

  it "keeps a workspace's name a caller argument, untouched by the rename" do
    expect(I18n.t("workspaces.joins.show.title", workspace_name: "COMP 4999")).to eq("Join COMP 4999")
  end

  it "reads the template's words again once the override is gone" do
    # An absent override, not a bare reload!: DEFAULTS_PATH is template-owned
    # (a fork only ever writes OVERRIDE_PATH), so this holds in every fork,
    # not just this checkout.
    Dir.mktmpdir do |dir|
      Vocabulary.reload!(override: Pathname.new(dir).join("absent.yml"))

      expect(I18n.t("onboarding.workspaces.new.title")).to eq("Name your workspace")
    end
  end
end
