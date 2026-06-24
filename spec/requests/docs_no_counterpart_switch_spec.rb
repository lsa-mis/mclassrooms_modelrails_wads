require "rails_helper"

# After switching audience on a doc that has no counterpart in the target mode,
# markdowndocs (>= the no-counterpart change, gem PR #28) redirects to that
# audience's index instead of stranding the reader on a doc outside the audience
# they chose, and sets a distinct "no version" flash. This app surfaces that
# flash as a toast pill. Guards the host integration with the app's
# user/developer modes (the gem's own specs use guide/technical).
RSpec.describe "Docs audience switch with no counterpart", type: :request do
  it "redirects to the index and flashes a 'no version' notice" do
    # user/authentication exists; there is no developer/authentication counterpart
    # and no shared-root authentication doc.
    patch "/docs/preference",
      params: { mode: "developer", current_path: "/docs/user/authentication" }
    expect(response).to redirect_to("/docs")

    follow_redirect!
    expect(response.body).to include("version of this page")
  end

  it "still keeps you on a doc that DOES have a counterpart (topic-preserving)" do
    # notifications is a 1:1 pair (user/notifications <-> developer/notifications).
    patch "/docs/preference",
      params: { mode: "developer", current_path: "/docs/user/notifications" }
    expect(response).to redirect_to("/docs/developer/notifications")
  end
end
