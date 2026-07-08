RSpec.shared_examples "a tenanted directory record" do
  # Caller must provide `record` (persisted) via let.
  it "belongs to a workspace and is invalid without one" do
    expect(record.workspace).to be_a(Workspace)
    record.workspace = nil
    expect(record).not_to be_valid
  end

  it "is scoped by for_current_workspace to the matching workspace" do
    Current.workspace = record.workspace
    expect(described_class.for_current_workspace).to include(record)
    Current.workspace = create(:workspace)
    expect(described_class.for_current_workspace).not_to include(record)
  end
end
