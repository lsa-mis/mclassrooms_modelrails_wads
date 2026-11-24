require "rails_helper"

RSpec.describe WorkspaceRoster do
  # Names and emails are pinned: a Faker email can contain another member's
  # first name ("alice.baker@…"), which made the exclusions flake (#467).
  def add_named_member(workspace, *traits, first:, last:)
    membership = create(:membership, *traits, workspace: workspace)
    membership.user.update!(first_name: first, last_name: last, email_address: "#{first}.#{last}@example.test".downcase)
    membership
  end

  def roster_members(workspace)
    [
      add_named_member(workspace, :owner, first: "Alice", last: "Anderson"),
      add_named_member(workspace, :admin, first: "Bob", last: "Baker"),
      add_named_member(workspace, first: "Carol", last: "Clark")
    ]
  end

  describe "search" do
    it "matches a member by first name" do
      workspace = create(:workspace)
      alice_membership, bob_membership, carol_membership = roster_members(workspace)
      roster = described_class.new(workspace)

      rows = roster.rows(q: "Alice")

      expect(rows).to include(alice_membership)
      expect(rows).not_to include(bob_membership, carol_membership)
    end

    it "matches a member by last name" do
      workspace = create(:workspace)
      _, bob_membership = roster_members(workspace)
      roster = described_class.new(workspace)

      expect(roster.rows(q: "Baker")).to contain_exactly(bob_membership)
    end

    it "matches a member by email address" do
      workspace = create(:workspace)
      _, _, carol_membership = roster_members(workspace)
      roster = described_class.new(workspace)

      expect(roster.rows(q: "carol.clark@example.test")).to contain_exactly(carol_membership)
    end

    it "is case-insensitive" do
      workspace = create(:workspace)
      alice_membership, = roster_members(workspace)
      roster = described_class.new(workspace)

      expect(roster.rows(q: "aLiCe")).to contain_exactly(alice_membership)
    end

    it "matches a pending invitation by email address" do
      workspace = create(:workspace)
      roster_members(workspace)
      roster = described_class.new(workspace)

      invitation = create(:invitation, invitable: workspace, email: "dana.dorsey@example.test")

      expect(roster.rows(q: "dorsey")).to contain_exactly(invitation)
    end

    it "returns every row for a blank query" do
      workspace = create(:workspace)
      alice_membership, bob_membership, carol_membership = roster_members(workspace)
      roster = described_class.new(workspace)

      expect(roster.rows(q: "")).to contain_exactly(alice_membership, bob_membership, carol_membership)
      expect(roster.rows(q: nil)).to contain_exactly(alice_membership, bob_membership, carol_membership)
    end

    # #454: `_` is a valid email local-part character. It must match itself,
    # never "any one character".
    it "treats SQL wildcard characters in the query as literal text" do
      workspace = create(:workspace)
      roster_members(workspace)
      roster = described_class.new(workspace)

      underscore = create(:invitation, invitable: workspace, email: "a_b@example.com")
      create(:invitation, invitable: workspace, email: "axb@example.com")

      expect(roster.rows(q: "a_b")).to contain_exactly(underscore)
    end
  end

  describe "order" do
    it "lists pending invitations before members" do
      workspace = create(:workspace)
      alice_membership, bob_membership, carol_membership = roster_members(workspace)
      roster = described_class.new(workspace)

      invitation = create(:invitation, invitable: workspace, email: "zed@example.test")

      expect(roster.rows.first).to eq(invitation)
      expect(roster.rows.last(3)).to contain_exactly(alice_membership, bob_membership, carol_membership)
    end

    it "sorts members by name ascending" do
      workspace = create(:workspace)
      roster_members(workspace)
      roster = described_class.new(workspace)

      names = roster.rows(sort: "name", direction: "asc").map { |m| m.user.first_name }

      expect(names).to eq(%w[Alice Bob Carol])
    end

    it "sorts members by name descending" do
      workspace = create(:workspace)
      roster_members(workspace)
      roster = described_class.new(workspace)

      names = roster.rows(sort: "name", direction: "desc").map { |m| m.user.first_name }

      expect(names).to eq(%w[Carol Bob Alice])
    end

    # #124: the sort headers render over the combined table, so invitation
    # rows honor them too — a control that applies to half the rows lies.
    it "applies the email sort to invitation rows" do
      workspace = create(:workspace)
      roster_members(workspace)
      roster = described_class.new(workspace)

      zzz = create(:invitation, invitable: workspace, email: "zzz@example.com")
      aaa = create(:invitation, invitable: workspace, email: "aaa@example.com")

      expect(roster.rows(sort: "email", direction: "asc").first(2)).to eq([ aaa, zzz ])
      expect(roster.rows(sort: "email", direction: "desc").first(2)).to eq([ zzz, aaa ])
    end

    it "sorts members by role name" do
      workspace = create(:workspace)
      roster_members(workspace)
      roster = described_class.new(workspace)

      role_names = roster.rows(sort: "role", direction: "asc").map { |m| m.role.name }

      expect(role_names).to eq(%w[Admin Member Owner])
    end

    it "defaults to newest first for an unknown column, whatever the direction" do
      workspace = create(:workspace)
      alice_membership, bob_membership, carol_membership = roster_members(workspace)
      roster = described_class.new(workspace)

      expect(roster.rows(sort: "unknown", direction: "asc")).to eq([ carol_membership, bob_membership, alice_membership ])
    end

    it "treats any direction but asc as descending" do
      workspace = create(:workspace)
      roster_members(workspace)
      roster = described_class.new(workspace)

      names = roster.rows(sort: "name", direction: "sideways").map { |m| m.user.first_name }

      expect(names).to eq(%w[Carol Bob Alice])
    end
  end
end
