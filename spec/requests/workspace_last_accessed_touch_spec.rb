require "rails_helper"

# Every workspace-scoped request stamps memberships.last_accessed_at. There are
# 20 controllers including WorkspaceScoped, so unguarded this is one write per
# page load on a single-writer SQLite database, serialized behind every other
# write — while every reader of the stamp (the workspaces sort, the row's "last
# seen" phrasing, the switcher's recency order) tolerates minute granularity
# (#171).
#
# The contract is about the WRITE, not the statement: a guarded update_all still
# issues its UPDATE, it just matches zero rows and appends no WAL. So these
# examples watch the stamp rather than counting queries.
RSpec.describe "Workspace last-accessed touch", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  it "does not re-stamp inside the window" do
    get workspace_path(workspace)
    first = membership.reload.last_accessed_at
    expect(first).to be_present

    # Well inside the window, and far enough that an unguarded touch would move
    # the stamp by a visible minute rather than by microseconds.
    travel 1.minute do
      expect { get workspace_path(workspace) }
        .not_to change { membership.reload.last_accessed_at }
    end
  end

  it "re-stamps once the window has passed" do
    get workspace_path(workspace)
    first = membership.reload.last_accessed_at

    travel 6.minutes do
      get workspace_path(workspace)
      expect(membership.reload.last_accessed_at).to be > first,
        "the stamp went stale and was never refreshed — the recency sort would freeze"
    end
  end

  it "stamps a membership that has never been accessed" do
    membership.update_column(:last_accessed_at, nil)

    expect { get workspace_path(workspace) }
      .to change { membership.reload.last_accessed_at }.from(nil)
  end
end
