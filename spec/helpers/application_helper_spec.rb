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

  # Task 10 (Navigation IA): current_grant is the single RoleResolver lookup
  # the nav (and, per app/lib/role_resolver.rb, phase 4/5 admin views) gates
  # on. Memoized per request/helper-instance; safe to call with no signed-in
  # user without a nil-guard because RoleResolver.for(nil) already resolves
  # to an all-false Grant (see spec/lib/role_resolver_spec.rb).
  describe "#current_grant" do
    it "returns an all-false Grant when Current.user is nil" do
      allow(Current).to receive(:user).and_return(nil)

      grant = helper.current_grant

      expect(grant.admin?).to be(false)
      expect(grant.viewer?).to be(false)
    end

    it "reflects the signed-in user's admin membership in the shared workspace" do
      workspace = create(:workspace, personal: false)
      user = create(:user)
      create(:membership, :admin, user: user, workspace: workspace)

      allow(TenancyConfig).to receive(:shared_workspace).and_return(workspace)
      allow(Current).to receive(:user).and_return(user)

      expect(helper.current_grant.admin?).to be(true)
    end

    it "memoizes within the same helper instance — only one RoleResolver.for call per request" do
      user = create(:user)
      allow(Current).to receive(:user).and_return(user)
      expect(RoleResolver).to receive(:for).once.with(user).and_call_original

      2.times { helper.current_grant }
    end

    it "returns the same Grant object on repeated calls (not just an equal one)" do
      allow(Current).to receive(:user).and_return(create(:user))

      first_call = helper.current_grant
      second_call = helper.current_grant

      expect(first_call).to equal(second_call)
    end
  end
end
