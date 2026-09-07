require "rails_helper"

RSpec.describe WorkspaceRoster do
  let(:workspace) { create(:workspace) }
  let(:roster) { described_class.new(workspace) }

  let!(:alice_membership) { create(:membership, :owner, workspace: workspace) }
  let!(:bob_membership) { create(:membership, :admin, workspace: workspace) }
  let!(:carol_membership) { create(:membership, workspace: workspace) }

  # Pinned alongside the names: a Faker email can contain another member's
  # first name ("alice.baker@…"), which would make the exclusion examples
  # flake (#467).
  before do
    alice_membership.user.update!(first_name: "Alice", last_name: "Anderson", email_address: "alice.anderson@example.test")
    bob_membership.user.update!(first_name: "Bob", last_name: "Baker", email_address: "bob.baker@example.test")
    carol_membership.user.update!(first_name: "Carol", last_name: "Clark", email_address: "carol.clark@example.test")
  end

  describe "search" do
    it "matches a member by first name" do
      rows = roster.rows(q: "Alice")

      expect(rows).to include(alice_membership)
      expect(rows).not_to include(bob_membership, carol_membership)
    end

    it "matches a member by last name" do
      expect(roster.rows(q: "Baker")).to contain_exactly(bob_membership)
    end

    it "matches a member by email address" do
      expect(roster.rows(q: "carol.clark@example.test")).to contain_exactly(carol_membership)
    end

    it "is case-insensitive" do
      expect(roster.rows(q: "aLiCe")).to contain_exactly(alice_membership)
    end

    it "matches a pending invitation by email address" do
      invitation = create(:invitation, invitable: workspace, email: "dana.dorsey@example.test")

      expect(roster.rows(q: "dorsey")).to contain_exactly(invitation)
    end

    it "returns every row for a blank query" do
      expect(roster.rows(q: "")).to contain_exactly(alice_membership, bob_membership, carol_membership)
      expect(roster.rows(q: nil)).to contain_exactly(alice_membership, bob_membership, carol_membership)
    end

    # #454: `_` is a valid email local-part character. It must match itself,
    # never "any one character".
    it "treats SQL wildcard characters in the query as literal text" do
      underscore = create(:invitation, invitable: workspace, email: "a_b@example.com")
      create(:invitation, invitable: workspace, email: "axb@example.com")

      expect(roster.rows(q: "a_b")).to contain_exactly(underscore)
    end
  end

  describe "order" do
    it "lists pending invitations before members" do
      invitation = create(:invitation, invitable: workspace, email: "zed@example.test")

      expect(roster.rows.first).to eq(invitation)
      expect(roster.rows.last(3)).to contain_exactly(alice_membership, bob_membership, carol_membership)
    end

    it "sorts members by name ascending" do
      names = roster.rows(sort: "name", direction: "asc").map { |m| m.user.first_name }

      expect(names).to eq(%w[Alice Bob Carol])
    end

    it "sorts members by name descending" do
      names = roster.rows(sort: "name", direction: "desc").map { |m| m.user.first_name }

      expect(names).to eq(%w[Carol Bob Alice])
    end

    # #124: the sort headers render over the combined table, so invitation
    # rows honor them too — a control that applies to half the rows lies.
    it "applies the email sort to invitation rows" do
      zzz = create(:invitation, invitable: workspace, email: "zzz@example.com")
      aaa = create(:invitation, invitable: workspace, email: "aaa@example.com")

      expect(roster.rows(sort: "email", direction: "asc").first(2)).to eq([ aaa, zzz ])
      expect(roster.rows(sort: "email", direction: "desc").first(2)).to eq([ zzz, aaa ])
    end

    it "sorts members by role name" do
      role_names = roster.rows(sort: "role", direction: "asc").map { |m| m.role.name }

      expect(role_names).to eq(%w[Admin Member Owner])
    end

    it "defaults to newest first for an unknown column, whatever the direction" do
      expect(roster.rows(sort: "unknown", direction: "asc")).to eq([ carol_membership, bob_membership, alice_membership ])
    end

    it "treats any direction but asc as descending" do
      names = roster.rows(sort: "name", direction: "sideways").map { |m| m.user.first_name }

      expect(names).to eq(%w[Carol Bob Alice])
    end
  end
end
