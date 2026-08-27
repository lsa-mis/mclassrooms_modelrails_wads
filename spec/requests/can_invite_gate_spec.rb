require "rails_helper"

# D5's deliverable is the WRITER INVENTORY, not just the predicate: every path
# that stamps `authentications.verified_at` is asserted against here, so a new
# writer that skips the round trip fails this file rather than silently
# widening who may send invitations.
RSpec.describe "User#can_invite? — verified_at writer inventory", type: :request do
  let(:user) { create(:user, :no_authentications, password: "SecureP@ssw0rd123!") }

  describe "writers that legitimately prove the address" do
    it "email round-trip: Authentication#verify! satisfies the gate" do
      auth = user.authentications.create!(provider: "email", uid: user.email_address)
      expect(user.reload.can_invite?).to be(false)

      auth.verify!

      expect(user.reload.can_invite?).to be(true)
    end

    it "provider-vouched OAuth: a verified oauth authentication satisfies the gate" do
      user.authentications.create!(provider: "google", uid: "g-1",
                                   email: user.email_address, verified_at: Time.current)

      expect(user.reload.can_invite?).to be(true)
    end
  end

  describe "writers that prove nothing about the address" do
    # Setting a password demonstrates control of the SESSION, not of the
    # mailbox. Stamping verified_at here let password-set alone satisfy the
    # invite gate without any email round trip.
    it "setting a password does not mark the address verified" do
      sign_in(user)
      user.update!(password_digest: nil)

      post settings_password_path, params: {
        user: { password: "An0ther-Passw0rd!", password_confirmation: "An0ther-Passw0rd!" }
      }

      auth = user.authentications.email.sole
      expect(auth.verified_at).to be_nil
      expect(auth).to be_pending
    end

    it "setting a password does not satisfy the invite gate" do
      sign_in(user)
      user.update!(password_digest: nil)

      post settings_password_path, params: {
        user: { password: "An0ther-Passw0rd!", password_confirmation: "An0ther-Passw0rd!" }
      }

      expect(user.reload.can_invite?).to be(false)
    end
  end

  # The gate at the surfaces, not just the predicate. ALL FOUR invitation
  # create paths include InvitationSending — including onboarding.
  #
  # Onboarding is safe to gate because every production path to a session
  # arrives with a verified authentication: verified OAuth stamps on both its
  # link and signup branches; magic-link registration stamps; password and
  # passkey sign-in are only reachable by someone who registered through one of
  # those; and UNVERIFIED OAuth does not sign the user in at all — OauthLink
  # returns :unverified_pending and the controller redirects to sign-in with a
  # "check your email" notice. There is no way to reach onboarding unverified.
  describe "the gate on an invitation surface" do
    let(:workspace) { create(:workspace) }
    let!(:membership) do
      create(:membership, user: user, workspace: workspace,
                          role: Role.system_default!("owner"))
    end

    it "refuses to send and says why when the sender is unverified" do
      sign_in(user)

      expect {
        post workspace_invitations_path(workspace),
             params: { invitation: { emails: "someone@example.test",
                                     role_id: Role.system_default!("member").id } }
      }.not_to change(Invitation, :count)

      expect(flash[:alert]).to eq(I18n.t("invitations.unverified_sender"))
    end
  end

  describe "the gate on onboarding, the fourth surface" do
    let(:unverified) { create(:user, :unverified_email, :with_zero_workspaces) }
    let(:workspace) { create(:workspace) }
    let!(:project) { create(:project, workspace: workspace) }

    before do
      allow(TenancyConfig).to receive(:onboarding).and_return(:none)
      workspace.memberships.create!(user: unverified, role: Role.system_default!("owner"))
      sign_in(unverified)
    end

    it "refuses invitations from an unverified sender during first-run too" do
      expect {
        post onboarding_team_path,
             params: { invitation: { emails: "someone@example.test",
                                     role_id: Role.system_default!("member").id } }
      }.not_to change(Invitation, :count)

      expect(flash[:alert]).to eq(I18n.t("invitations.unverified_sender"))
    end
  end

  describe "a user with no authentication at all" do
    it "cannot invite" do
      expect(user.can_invite?).to be(false)
    end
  end
end
