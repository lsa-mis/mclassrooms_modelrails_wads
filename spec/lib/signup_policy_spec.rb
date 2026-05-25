require "rails_helper"

RSpec.describe SignupPolicy do
  describe ".allows_signup?" do
    context "when SIGNUP_MODE is :open" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      end

      it "returns true with no token" do
        expect(SignupPolicy.allows_signup?(token: nil)).to be true
      end

      it "returns true with a blank token" do
        expect(SignupPolicy.allows_signup?(token: "")).to be true
      end

      it "returns true even when the token does not match any invitation" do
        expect(SignupPolicy.allows_signup?(token: "nonsense")).to be true
      end
    end

    context "when SIGNUP_MODE is :invite_only" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      end

      it "returns false with no token" do
        expect(SignupPolicy.allows_signup?(token: nil)).to be false
      end

      it "returns false with a blank token" do
        expect(SignupPolicy.allows_signup?(token: "")).to be false
      end

      it "returns false with a non-matching token string" do
        expect(SignupPolicy.allows_signup?(token: "garbage")).to be false
      end

      it "returns false for an expired invitation token" do
        invitation = create(:invitation, :expired)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be false
      end

      it "returns false for an already-accepted invitation" do
        invitation = create(:invitation, :accepted)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be false
      end

      it "returns false for a declined invitation" do
        invitation = create(:invitation, :declined)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be false
      end

      it "returns false for a revoked invitation" do
        invitation = create(:invitation, :revoked)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be false
      end

      it "returns true for a valid pending invitation token" do
        invitation = create(:invitation)
        expect(SignupPolicy.allows_signup?(token: invitation.token)).to be true
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
end
