require "rails_helper"

# The recurring 2:30am trigger only resolves the directory workspace and enqueues SyncRunJob.
RSpec.describe SyncNightlyJob, type: :job do
  include ActiveJob::TestHelper

  let(:shared_workspace) { create(:workspace, slug: "shared-sync-test", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared_workspace.slug)
  end

  it "enqueues the directory's sync, with no operator behind it" do
    described_class.new.perform

    expect(SyncRunJob).to have_been_enqueued.with(shared_workspace)
  end

  it "fails loudly when the directory workspace is missing, a setup bug rather than a sync failure" do
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return("no-such-workspace")

    expect { described_class.new.perform }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
