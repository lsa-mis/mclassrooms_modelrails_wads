require "rails_helper"

# The stamp writes at most once per window (#171). A guarded UPDATE still runs,
# matching no rows, so these watch the stamp rather than counting queries.
RSpec.describe "Workspace last-accessed touch", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  it "does not re-stamp inside the window" do
    get workspace_path(workspace)
    first = membership.reload.last_accessed_at
    expect(first).to be_present

    # Inside the window, and far enough that a stray touch moves a whole minute.
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
