require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#safe_html" do
    it "marks trusted HTML as safe so ERB output does not escape it" do
      result = helper.safe_html("<p>hi</p>")

      expect(result).to be_html_safe
      expect(result.to_s).to eq("<p>hi</p>")
    end

    it "returns nil unchanged when given nil" do
      expect(helper.safe_html(nil)).to be_nil
    end
  end

  describe "#sidebar_workspaces_scope" do
    let(:user) { create(:user) }

    before { allow(Current).to receive(:user).and_return(user) }

    # :logo_attachment is always included — needed by the workspace switcher
    # icon regardless of posture.
    it "always includes :logo_attachment in the eager-loads" do
      scope = helper.sidebar_workspaces_scope
      expect(scope.includes_values).to include(:logo_attachment)
    end

    context "under :personal onboarding posture" do
      before do
        allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:personal)
      end

      it "includes memberships in the eager-loads (needed for owner-avatar fallback)" do
        scope = helper.sidebar_workspaces_scope
        # includes_values may contain memberships as a symbol or as a Hash key;
        # flatten one level to check presence in either form.
        flat = scope.includes_values.flat_map { |v| v.is_a?(Hash) ? v.keys : v }
        expect(flat).to include(:memberships)
      end
    end

    context "under :none onboarding posture" do
      before do
        allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:none)
      end

      it "does NOT include memberships in the eager-loads (no personal workspaces → dead weight)" do
        scope = helper.sidebar_workspaces_scope
        flat = scope.includes_values.flat_map { |v| v.is_a?(Hash) ? v.keys : v }
        expect(flat).not_to include(:memberships)
      end
    end
  end
end
