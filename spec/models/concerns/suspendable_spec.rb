require "rails_helper"

RSpec.describe Suspendable, type: :model do
  let(:record) { create(:workspace) }

  describe "#suspend!" do
    it "sets suspended_at to current time" do
      freeze_time do
        record.suspend!
        expect(record.suspended_at).to eq(Time.current)
      end
    end
  end

  describe "#unsuspend!" do
    it "clears suspended_at" do
      record.suspend!
      record.unsuspend!
      expect(record.suspended_at).to be_nil
    end
  end

  describe "scopes" do
    let!(:normal_record) { create(:workspace) }
    let!(:suspended_record) { create(:workspace).tap(&:suspend!) }

    it "not_suspended excludes suspended" do
      expect(Workspace.not_suspended).to include(normal_record)
      expect(Workspace.not_suspended).not_to include(suspended_record)
    end

    it "suspended includes only suspended" do
      expect(Workspace.suspended).to include(suspended_record)
      expect(Workspace.suspended).not_to include(normal_record)
    end
  end

  describe "SuspendedError" do
    it "is a StandardError available at the concern level" do
      expect(Suspendable::SuspendedError.ancestors).to include(StandardError)
    end
  end

  it "is not included in Membership (workspace-only state)" do
    expect(Membership.ancestors).not_to include(Suspendable)
  end
end
