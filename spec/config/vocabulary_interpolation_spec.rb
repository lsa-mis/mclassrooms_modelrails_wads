require "rails_helper"
require "tmpdir"

# The one backend customization in the app. Behavior is asserted against the
# real backend and real keys, not a stub: the failure modes this guards were
# found in a spike (the gem skips interpolation on value-less calls; a
# vocabulary that fills a caller's forgotten argument masks a bug).
#
# The examples below assert the template's actual words ("workspace",
# "project"), so they pin the vocabulary to those words for the duration —
# otherwise a renamed fork reads its own words back and every assertion here
# goes red for a reason that has nothing to do with the hook's mechanics.
RSpec.describe "Vocabulary interpolation", type: :config do
  around do |example|
    Dir.mktmpdir do |dir|
      override = Pathname.new(dir).join("vocabulary.local.yml")
      override.write(%(workspace: { singular: "workspace", plural: "workspaces" }\nproject: { singular: "project", plural: "projects" }\n))
      Vocabulary.reload!(override: override)
      example.run
    ensure
      Vocabulary.reload!
    end
  end

  before do
    I18n.backend.store_translations(:en, vocab_probe: {
      bare: "%{Workspace} not found.",
      mixed: "Join %{workspace_name}, your new %{workspace}.",
      counted: { one: "%{count} %{project}", other: "%{count} %{projects}" },
      plain: "No tokens here.",
      client_filled: "Draft restored. %{count} fields updated.",
      client_filled_with_noun: { one: "%{count} %{project} restored", other: "%{count} %{projects} restored" }
    })
  end

  after { I18n.backend.reload! }

  it "fills vocabulary tokens when the caller passes no values" do
    expect(I18n.t("vocab_probe.bare")).to eq("Workspace not found.")
  end

  it "fills them alongside the caller's own arguments" do
    expect(I18n.t("vocab_probe.mixed", workspace_name: "COMP 4999")).to eq("Join COMP 4999, your new workspace.")
  end

  it "fills them on every pluralization branch" do
    expect(I18n.t("vocab_probe.counted", count: 1)).to eq("1 project")
    expect(I18n.t("vocab_probe.counted", count: 3)).to eq("3 projects")
  end

  it "still raises when the caller forgets a name argument" do
    expect { I18n.t("vocab_probe.mixed") }.to raise_error(I18n::MissingInterpolationArgument, /workspace_name/)
  end

  it "lets a caller override a vocabulary token for one call" do
    expect(I18n.t("vocab_probe.bare", Workspace: "Cohort")).to eq("Cohort not found.")
  end

  it "reaches the view helper path" do
    expect(ApplicationController.helpers.t("vocab_probe.bare")).to eq("Workspace not found.")
  end

  it "leaves a token-free string alone" do
    expect(I18n.t("vocab_probe.plain")).to eq("No tokens here.")
  end

  it "leaves a placeholder that JavaScript fills untouched when the caller passes nothing" do
    expect(I18n.t("vocab_probe.client_filled")).to eq("Draft restored. %{count} fields updated.")
  end

  it "still interpolates that placeholder when the caller supplies it" do
    expect(I18n.t("vocab_probe.client_filled", count: 3)).to eq("Draft restored. 3 fields updated.")
  end

  it "fills the nouns in a string that also carries a caller-supplied count" do
    expect(I18n.t("vocab_probe.client_filled_with_noun", count: 2)).to eq("2 projects restored")
  end

  it "renders the real form-draft notice with its placeholder intact" do
    expect(I18n.t("form_draft.restored_other")).to include("%{count}")
  end

  it "leaves a literal default with a client-filled placeholder alone when the key is nil" do
    expect(I18n.t(nil, default: "Draft restored. %{count} fields updated.")).to eq("Draft restored. %{count} fields updated.")
  end
end
