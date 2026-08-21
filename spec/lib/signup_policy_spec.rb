require "rails_helper"

RSpec.describe SignupPolicy do
  describe ".allows_signup?" do
    context "when SIGNUP_MODE is :open" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      end

      it "returns true with no token" do
        expect(SignupPolicy.allows_signup?(invitation_token: nil)).to be true
      end

      it "returns true with a blank token" do
        expect(SignupPolicy.allows_signup?(invitation_token: "")).to be true
      end

      it "returns true even when the token does not match any invitation" do
        expect(SignupPolicy.allows_signup?(invitation_token: "nonsense")).to be true
      end
    end

    context "when SIGNUP_MODE is :invite_only" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      end

      it "returns false with no token" do
        expect(SignupPolicy.allows_signup?(invitation_token: nil)).to be false
      end

      it "returns false with a blank token" do
        expect(SignupPolicy.allows_signup?(invitation_token: "")).to be false
      end

      it "returns false with a non-matching token string" do
        expect(SignupPolicy.allows_signup?(invitation_token: "garbage")).to be false
      end

      it "returns false for an expired invitation token" do
        invitation = create(:invitation, :expired)
        expect(SignupPolicy.allows_signup?(invitation_token: invitation.token)).to be false
      end

      it "returns false for an already-accepted invitation" do
        invitation = create(:invitation, :accepted)
        expect(SignupPolicy.allows_signup?(invitation_token: invitation.token)).to be false
      end

      it "returns false for a declined invitation" do
        invitation = create(:invitation, :declined)
        expect(SignupPolicy.allows_signup?(invitation_token: invitation.token)).to be false
      end

      it "returns false for a revoked invitation" do
        invitation = create(:invitation, :revoked)
        expect(SignupPolicy.allows_signup?(invitation_token: invitation.token)).to be false
      end

      it "returns true for a valid pending invitation token" do
        invitation = create(:invitation)
        expect(SignupPolicy.allows_signup?(invitation_token: invitation.token)).to be true
      end
    end
  end

  # The join-link OR-branch is private implementation of allows_signup? —
  # exercised through the public gate with the config mode held closed so the
  # join_token alone decides the outcome.
  describe "the workspace join-link branch of .allows_signup?" do
    let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
    let(:link) { create(:workspace_join_link, workspace: workspace, created_by: create(:user)) }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    end

    it "opens the gate for an active link of an open-join workspace" do
      expect(SignupPolicy.allows_signup?(join_token: link.plaintext_token)).to be true
    end

    it "keeps the gate closed for a blank or unknown token" do
      expect(SignupPolicy.allows_signup?(join_token: nil)).to be false
      expect(SignupPolicy.allows_signup?(join_token: "")).to be false
      expect(SignupPolicy.allows_signup?(join_token: "does-not-exist")).to be false
    end

    it "keeps the gate closed for a revoked link" do
      link.revoke!
      expect(SignupPolicy.allows_signup?(join_token: link.plaintext_token)).to be false
    end

    it "keeps the gate closed when the workspace's policy isn't open_link" do
      workspace.update!(join_policy: "invite")
      expect(SignupPolicy.allows_signup?(join_token: link.plaintext_token)).to be false
    end

    it "keeps the gate closed when the instance allowlist excludes :open_link" do
      link # materialize while permissive allowlist is in effect
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      expect(SignupPolicy.allows_signup?(join_token: link.plaintext_token)).to be false
    end
  end

  describe ".allows_signup? with join_token: kwarg (Reshape 2b)" do
    let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
    let(:link) { create(:workspace_join_link, workspace: workspace, created_by: create(:user)) }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    end

    it "opens the gate when a valid open-link join_token is supplied" do
      expect(SignupPolicy.allows_signup?(join_token: link.plaintext_token)).to be true
    end

    it "keeps the gate closed for an unknown join_token" do
      expect(SignupPolicy.allows_signup?(join_token: "nope")).to be false
    end

    it "opens the gate via the invitation_token: kwarg (invitation path)" do
      invitation = create(:invitation)
      expect(SignupPolicy.allows_signup?(invitation_token: invitation.token)).to be true
    end

    it "either kwarg opens the gate (composable)" do
      invitation = create(:invitation)
      expect(SignupPolicy.allows_signup?(invitation_token: invitation.token, join_token: nil)).to be true
      expect(SignupPolicy.allows_signup?(invitation_token: nil, join_token: link.plaintext_token)).to be true
    end
  end
end
