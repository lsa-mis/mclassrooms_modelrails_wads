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

  describe ".config_allows_signup?" do
    it "returns true when mode is :open" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      expect(SignupPolicy.config_allows_signup?).to be true
    end

    it "returns false when mode is :invite_only" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      expect(SignupPolicy.config_allows_signup?).to be false
    end
  end

  describe ".workspace_join_acceptable?" do
    let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
    let(:link) { create(:workspace_join_link, workspace: workspace, created_by: create(:user)) }

    before do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    end

    it "returns true for an active link of an open-join workspace" do
      expect(SignupPolicy.workspace_join_acceptable?(link.plaintext_token)).to be true
    end

    it "returns false for a blank or unknown token" do
      expect(SignupPolicy.workspace_join_acceptable?(nil)).to be false
      expect(SignupPolicy.workspace_join_acceptable?("")).to be false
      expect(SignupPolicy.workspace_join_acceptable?("does-not-exist")).to be false
    end

    it "returns false for a revoked link" do
      link.revoke!
      expect(SignupPolicy.workspace_join_acceptable?(link.plaintext_token)).to be false
    end

    it "returns false when the workspace's policy isn't open_link" do
      workspace.update!(join_policy: "invite")
      expect(SignupPolicy.workspace_join_acceptable?(link.plaintext_token)).to be false
    end

    it "returns false when the instance allowlist excludes :open_link" do
      link  # materialize while permissive allowlist is in effect
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      expect(SignupPolicy.workspace_join_acceptable?(link.plaintext_token)).to be false
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
