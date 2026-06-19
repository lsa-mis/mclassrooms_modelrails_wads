# frozen_string_literal: true

require "rails_helper"

# Guards docs/deprecations.md for the things the team agreed to track:
#
# 1. The known call-sites where `Workspace#personal?` leaks into presentation —
#    so future contributors can find them without grepping.
# 2. A "removal trigger" phrase — ensures the doc answers "when should we act?"
#    rather than just describing debt.
#
# This spec intentionally tests *content shape*, not wording, so minor prose
# edits don't break CI. Add a new assertion only when the team commits to
# tracking a new invariant in the doc.
#
# Note: settings_context_kind was removed in Phase 2 (feat/workspace-settings-ia-phase2).
# Its entry has been removed from the doc and this spec accordingly.
RSpec.describe "docs/deprecations.md", type: :model do
  let(:doc_path) { Rails.root.join("docs/deprecations.md") }
  let(:content)  { doc_path.read }

  it "exists" do
    expect(doc_path).to exist
  end

  # workspace_icon_for remains the active presentation-layer call-site.
  # We match on the helper/file name, not the full line.
  it "mentions workspace_icon_for (workspace_helper debt call-site)" do
    expect(content).to include("workspace_icon_for")
  end

  # The doc must name a removal trigger so the debt is time-boxed to a
  # real event rather than left open-ended.
  it "contains a removal trigger phrase" do
    expect(content).to match(/removal trigger/i)
  end
end
