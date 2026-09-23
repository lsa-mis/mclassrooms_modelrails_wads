require "rails_helper"

RSpec.describe ActivityLog::Search do
  # The operator's reach, as the controller passes it: a relation, never a
  # predicate (User#operated_workspaces).
  let(:reach) { Workspace.kept }

  it "is blank and matches nothing without a query" do
    search = described_class.resolve("   ", reach: reach)

    expect(search).to be_blank
    expect(search).not_to be_matched
    expect(search.users).to be_empty
    expect(search.workspaces).to be_empty
    expect(search.projects).to be_empty
  end

  it "matches an email address exactly, whatever its case" do
    person = create(:user, email_address: "priya@example.com")
    create(:user, email_address: "other@example.com")

    search = described_class.resolve("  PRIYA@example.com ", reach: reach)

    expect(search).to be_matched
    expect(search.users.map(&:id)).to eq([ person.id ])
    # An address that is nobody's is a search that matched nothing, not a
    # blank one — the ledger owes the operator the difference.
    expect(described_class.resolve("nobody@example.com", reach: reach)).not_to be_matched
    expect(described_class.resolve("nobody@example.com", reach: reach)).not_to be_blank
  end

  it "matches a name anywhere in the first name, the last name or the two together" do
    nair = create(:user, first_name: "Priya", last_name: "Nair")
    patel = create(:user, first_name: "Priya", last_name: "Patel")
    other = create(:user, first_name: "Quinn", last_name: "Zeleny")

    expect(described_class.resolve("priya", reach: reach).users.map(&:id))
      .to contain_exactly(nair.id, patel.id)
    expect(described_class.resolve("NAI", reach: reach).users.map(&:id)).to include(nair.id)
    expect(described_class.resolve("ya na", reach: reach).users.map(&:id)).to eq([ nair.id ])
    expect(described_class.resolve("priya", reach: reach).users.map(&:id)).not_to include(other.id)
  end

  it "caps the users a broad query can return" do
    stub_const("User::Search::RESULT_LIMIT", 2)
    3.times { |n| create(:user, first_name: "Zeph#{n}", last_name: "Quilling") }

    expect(described_class.resolve("quilling", reach: reach).users.size).to eq(2)
  end

  it "does not search names on an instance over the name limit, and says so" do
    person = create(:user, first_name: "Priya", last_name: "Nair", email_address: "priya@example.com")
    stub_const("User::Search::NAME_SEARCH_LIMIT", 0)

    by_name = described_class.resolve("priya", reach: reach)
    expect(by_name).to be_names_skipped
    expect(by_name.users).to be_empty

    # The exact-email lookup is unaffected — it is SQL, not a decrypt pass.
    by_email = described_class.resolve("priya@example.com", reach: reach)
    expect(by_email.users.map(&:id)).to eq([ person.id ])
    expect(described_class.resolve("priya", reach: Workspace.none)).to be_names_skipped
  end

  it "does not report skipped names on an instance under the limit" do
    create(:user)

    expect(described_class.resolve("anything", reach: reach)).not_to be_names_skipped
  end

  it "matches a workspace by a name fragment or its exact slug, inside the reach only" do
    acme = create(:workspace, name: "Acme Robotics")
    beta = create(:workspace, name: "Beta Works")

    expect(described_class.resolve("robot", reach: reach).workspaces.map(&:id)).to eq([ acme.id ])
    expect(described_class.resolve(acme.slug, reach: reach).workspaces.map(&:id)).to eq([ acme.id ])
    # Out of reach is out of the result, whatever the name says.
    narrowed = described_class.resolve("robot", reach: Workspace.where(id: beta.id))
    expect(narrowed.workspaces).to be_empty
  end

  it "treats a query as text, never as a LIKE pattern" do
    create(:workspace, name: "Acme Robotics")
    literal = create(:workspace, name: "Ac_e Robotics")

    expect(described_class.resolve("ac_e", reach: reach).workspaces.map(&:id)).to eq([ literal.id ])
  end

  it "matches a project by name, inside the reach only" do
    acme = create(:workspace, name: "Acme Robotics")
    beta = create(:workspace, name: "Beta Works")
    launch = create(:project, workspace: acme, name: "Launch plan")
    create(:project, workspace: beta, name: "Launch elsewhere")

    expect(described_class.resolve("launch plan", reach: reach).projects.map(&:id)).to eq([ launch.id ])
    narrowed = described_class.resolve("launch", reach: Workspace.where(id: acme.id))
    expect(narrowed.projects.map(&:id)).to eq([ launch.id ])
  end
end
