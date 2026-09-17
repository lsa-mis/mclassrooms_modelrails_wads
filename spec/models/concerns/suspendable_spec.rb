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

    it "returns :suspended then :already_suspended on a repeat, leaving suspended_at and updated_at unchanged" do
      freeze_time { expect(record.suspend!).to eq(:suspended) }
      suspended_at = record.suspended_at
      updated_at = record.updated_at

      travel 1.hour do
        expect(record.suspend!).to eq(:already_suspended)
      end

      expect(record.reload.suspended_at).to eq(suspended_at)
      expect(record.updated_at).to eq(updated_at)
    end
  end

  describe "#unsuspend!" do
    it "clears suspended_at" do
      record.suspend!
      record.unsuspend!
      expect(record.suspended_at).to be_nil
    end

    it "returns :unsuspended then :not_suspended on a repeat, leaving updated_at unchanged" do
      record.suspend!
      freeze_time { expect(record.unsuspend!).to eq(:unsuspended) }
      updated_at = record.updated_at

      travel 1.hour do
        expect(record.unsuspend!).to eq(:not_suspended)
      end

      expect(record.reload.updated_at).to eq(updated_at)
    end
  end

  describe "a stale in-memory copy" do
    # lock! reloads the record under the writer lock before the check runs,
    # so copy B sees copy A's committed suspension even though its own
    # in-memory suspended_at was still nil when suspend! was called on it.
    it "still guards correctly, via lock!'s reload, and writes one activity row total" do
      copy_a = Workspace.find(record.id)
      copy_b = Workspace.find(record.id)

      expect {
        expect(copy_a.suspend!).to eq(:suspended)
        expect(copy_b.suspend!).to eq(:already_suspended)
      }.to change { record.activities.count }.by(1)
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
