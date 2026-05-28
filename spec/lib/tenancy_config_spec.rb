require "rails_helper"

RSpec.describe TenancyConfig do
  describe "defaults" do
    it "defaults onboarding to :personal" do
      expect(described_class.onboarding).to eq(:personal)
      expect(described_class).to be_personal
      expect(described_class).not_to be_shared
    end

    it "defaults workspace_creation to enabled" do
      expect(described_class).to be_workspace_creation_enabled
    end

    it "has no shared workspace slug by default" do
      expect(described_class.shared_workspace_slug).to be_nil
      expect(described_class.shared_workspace).to be_nil
    end
  end

  describe "under :shared onboarding" do
    let(:workspace) { create(:workspace, slug: "acme", personal: false) }

    before do
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
      allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    end

    it "reports shared? true" do
      expect(described_class).to be_shared
      expect(described_class).not_to be_personal
    end

    it "resolves the shared workspace by slug" do
      expect(described_class.shared_workspace).to eq(workspace)
    end

    it "returns nil when the configured slug doesn't match any workspace" do
      allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return("does-not-exist")
      expect(described_class.shared_workspace).to be_nil
    end
  end

  describe "workspace_creation_enabled?" do
    it "is false when configured :disabled" do
      allow(Rails.configuration.x.tenancy).to receive(:workspace_creation).and_return(:disabled)
      expect(described_class).not_to be_workspace_creation_enabled
    end
  end
end
