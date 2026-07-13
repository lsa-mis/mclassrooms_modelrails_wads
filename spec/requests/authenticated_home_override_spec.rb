require "rails_helper"

# Fork override of the template's authenticated-landing seam
# (ApplicationController#authenticated_home_path, overriding Authenticatable's
# default). Under the shared directory posture, signing in drops a NON-ADMIN
# straight into the product — Find a Room — once, at authentication time;
# root itself never redirects (spec/requests/pages_home_spec.rb pins that
# side). The template's own default is pinned by
# spec/requests/authenticated_landing_spec.rb and stays intact: the test env
# runs the :personal posture, where this override falls back to root.
RSpec.describe "Post-sign-in destination (fork seam override)", type: :request do
  let(:workspace) { create(:workspace, slug: "auth-home-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  # A real authentication request (not the sign_in helper's session shortcut)
  # so the redirect exercises after_authentication_url end-to-end.
  def password_sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }
  end

  it "drops a viewer into Find a Room" do
    password_sign_in(membership_with("viewer"))

    expect(response).to redirect_to(find_a_room_url)
  end

  it "keeps an admin on the landing page" do
    password_sign_in(membership_with("admin"))

    expect(response).to redirect_to(root_url)
  end

  # Same admittable gate DirectoryScoped uses: a suspended shared workspace
  # sends the user to the landing instead of chaining a redirect through
  # /find-a-room and back.
  it "falls back to the landing when the shared workspace is suspended" do
    viewer = membership_with("viewer")
    workspace.update!(suspended_at: Time.current)

    password_sign_in(viewer)

    expect(response).to redirect_to(root_url)
  end

  it "still honors a saved return_to over the product default" do
    viewer = membership_with("viewer")
    get edit_settings_profile_path
    expect(response).to redirect_to(new_session_path)

    password_sign_in(viewer)

    expect(response).to redirect_to(edit_settings_profile_url)
  end
end
