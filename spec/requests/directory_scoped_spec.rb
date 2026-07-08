require "rails_helper"

# Concern spec via an anonymous controller — the house pattern this suite
# already uses for controller concerns (see spec/controllers/concerns/
# toastable_spec.rb, signupable_spec.rb, and spec/requests/
# application_controller_spec.rb, which also lives under spec/requests/ but
# declares `type: :controller` explicitly, same as here). DirectoryScoped has
# no real including controller yet (product controllers land in later
# phases), so there is no "real controller" to exercise instead.
#
# The isolated route set below draws stand-ins for both redirect targets the
# concern (and the Authenticatable it composes) can hit: `root` and
# `new_session`. Assertions compare against literal paths rather than calling
# the `root_path`/`new_session_path` helpers from the example group, since
# those helpers would resolve against whichever route set `method_missing`
# happens to delegate to (ambiguous across the isolated vs. real app route
# sets) — literal path strings sidestep that entirely.
RSpec.describe DirectoryScoped, type: :controller do
  controller(ApplicationController) do
    include DirectoryScoped

    def index
      render plain: Current.workspace.slug
    end
  end

  before do
    routes.draw do
      get "index" => "anonymous#index"
      get "session/new" => "sessions#new", as: :new_session
      root "anonymous#index"
    end
  end

  let(:workspace) { create(:workspace, slug: "directory-test", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  describe "signed-in request" do
    let(:user) { create(:user) }
    let!(:session_record) { user.sessions.create!(user_agent: "RSpec", ip_address: "127.0.0.1") }

    before { cookies.signed[:session_id] = session_record.id }

    it "sets Current.workspace to the shared workspace (observable in the response)" do
      get :index
      expect(response.body).to eq(workspace.slug)
    end
  end

  describe "unauthenticated request" do
    it "redirects to sign-in instead of setting a workspace" do
      get :index
      expect(response).to redirect_to("/session/new")
    end
  end

  describe "suspended shared workspace" do
    let(:user) { create(:user) }
    let!(:session_record) { user.sessions.create!(user_agent: "RSpec", ip_address: "127.0.0.1") }

    before do
      cookies.signed[:session_id] = session_record.id
      workspace.suspend!
    end

    it "redirects to root with the locked notice instead of raising" do
      get :index
      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(I18n.t("workspaces.locked_notice"))
    end
  end

  describe "shared workspace slug resolves to nothing kept" do
    let(:user) { create(:user) }
    let!(:session_record) { user.sessions.create!(user_agent: "RSpec", ip_address: "127.0.0.1") }

    before do
      cookies.signed[:session_id] = session_record.id
      # Simulates a discarded shared workspace. Workspace#discard! itself is
      # guarded against this (raises HomeWorkspaceProtectedError for the
      # :shared posture's home workspace — see Workspace#home?/#discard!), so
      # this can't happen through the app's own mutators; bypass via
      # update_column to pin the defense-in-depth rescue branch anyway (e.g.
      # a stale/misconfigured TENANCY_SHARED_WORKSPACE_SLUG would hit the
      # same branch).
      workspace.update_column(:discarded_at, Time.current)
    end

    it "redirects to root with the not_found notice instead of a 500" do
      get :index
      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(I18n.t("workspaces.not_found"))
    end
  end
end
