require "rails_helper"

RSpec.describe ActivityLog, "ledger filters" do
  describe "KINDS" do
    # The Kind filter's options come from this list; the sentences come from
    # the locale tree. They must name the same set or an option renders a
    # missing-translation marker (dev) or raises (test).
    it "matches the action families the locale tree knows" do
      expect(described_class::KINDS).to match_array(I18n.t("activity.actions").keys.map(&:to_s))
    end
  end

  describe ".of_kind" do
    it "filters on the stored action prefix" do
      workspace = create(:workspace)
      create(:project, workspace: workspace)

      kinds = described_class.of_kind("project").pluck(:action)
      expect(kinds).to all(start_with("project."))
      expect(kinds).not_to be_empty
      expect(described_class.of_kind("membership").pluck(:action)).to all(start_with("membership."))
    end
  end

  describe ".involving" do
    it "matches rows where the user is the actor, the trackable, or the member of a tracked membership" do
      actor = create(:user)
      subject_user = create(:user)
      workspace = create(:workspace)
      membership = create(:membership, user: subject_user, workspace: workspace)

      session = actor.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      Current.session = session
      begin
        membership.update!(role: Role.system_default!("admin"))
      ensure
        Current.session = nil
      end
      described_class.record_security_event!(action: "user.unlocked", user: subject_user, actor: actor, visibility: "admin")

      expect(described_class.involving(actor).where(actor_id: actor.id)).to exist
      expect(described_class.involving(subject_user).where(trackable: subject_user)).to exist
      expect(described_class.involving(subject_user).where(trackable: membership)).to exist
      expect(described_class.involving(create(:user)).where(trackable: membership)).not_to exist
    end
  end

  describe ".matching_any" do
    # Acting AS someone is a session, not an assignment: Current.user delegates
    # to Current.session.
    def acting_as(user)
      Current.session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      yield
    ensure
      Current.session = nil
    end

    it "matches a user as actor, as trackable, and through a membership of theirs" do
      actor = create(:user)
      workspace = create(:workspace)
      membership = create(:membership, user: actor, workspace: workspace)
      acting_as(create(:user)) { membership.update!(role: Role.system_default!("admin")) }
      described_class.record_security_event!(action: "user.unlocked", user: actor,
                                             actor: create(:user), visibility: "admin")
      acting_as(actor) { create(:project, workspace: workspace) }

      scoped = described_class.matching_any(users: [ actor ], workspaces: [], projects: [])
      expect(scoped.where(actor_id: actor.id)).to exist
      expect(scoped.where(trackable: actor)).to exist
      expect(scoped.where(trackable: membership)).to exist
      expect(described_class.matching_any(users: [ create(:user) ], workspaces: [], projects: [])
               .where(trackable: membership)).not_to exist
    end

    it "matches a workspace's rows and a project's own rows" do
      acme = create(:workspace)
      beta = create(:workspace)
      project = create(:project, workspace: acme)

      by_workspace = described_class.matching_any(users: [], workspaces: [ acme ], projects: [])
      expect(by_workspace.pluck(:workspace_id).uniq).to eq([ acme.id ])
      expect(by_workspace.where(workspace_id: beta.id)).not_to exist

      by_project = described_class.matching_any(users: [], workspaces: [], projects: [ project ])
      expect(by_project.where(trackable: project)).to exist
      expect(by_project.where(trackable_type: "Workspace")).not_to exist
    end

    it "ORs the groups rather than intersecting them" do
      acme = create(:workspace)
      beta = create(:workspace)
      person = create(:user)
      acting_as(person) { create(:project, workspace: beta) }

      scoped = described_class.matching_any(users: [ person ], workspaces: [ acme ], projects: [])
      expect(scoped.where(workspace_id: acme.id)).to exist
      expect(scoped.where(actor_id: person.id)).to exist
    end

    it "matches nothing when every group is empty" do
      create(:workspace)

      expect(described_class.matching_any(users: [], workspaces: [], projects: [])).to be_empty
    end
  end

  describe ".within and .oldest_first" do
    it "bounds by created_at and can reverse the feed order" do
      workspace = create(:workspace)
      old = create(:project, workspace: workspace).activities.first
      # ActivityLog#readonly? blocks instance-level update_column too (it's
      # persisted?-gated, not save-path-specific) — go relation-level, same
      # door the retention sweep job uses (spec/code_smells/activity_log_immutability_spec.rb).
      described_class.where(id: old.id).update_all(created_at: 40.days.ago)
      old.reload
      recent = create(:project, workspace: workspace).activities.first

      scoped = described_class.for_operations_feed.within(30.days.ago, Time.current)
      expect(scoped).to include(recent)
      expect(scoped).not_to include(old)
      expect(described_class.for_operations_feed.oldest_first.first).to eq(old)
    end
  end

  # workspaces.name is plaintext, so this is the one column besides time the
  # ledger can sort in SQL. Instance-level rows have no name to sort by and
  # sit last in either direction, so "Instance" never reads as a name that
  # happens to sort first.
  describe ".by_workspace_name" do
    it "orders by name case-insensitively, newest first within a workspace, instance rows last" do
      beta = create(:workspace, name: "beta")
      alpha = create(:workspace, name: "Alpha")
      instance_row = described_class.create!(action: "user.suspended", visibility: "admin",
                                              trackable: create(:user), workspace: nil)
      first_alpha = alpha.activity_logs.first
      described_class.where(id: first_alpha.id).update_all(created_at: 2.days.ago)
      newer_alpha = create(:project, workspace: alpha).activities.first

      scope = described_class.for_operations_feed.where(id: [ beta.activity_logs, alpha.activity_logs, instance_row ].flatten.map(&:id))
      ascending = scope.by_workspace_name("asc").to_a
      expect(ascending.map(&:workspace_id).uniq).to eq([ alpha.id, beta.id, nil ])
      expect(ascending.index(newer_alpha)).to be < ascending.index(first_alpha)

      descending = scope.by_workspace_name("desc").to_a
      expect(descending.map(&:workspace_id).uniq).to eq([ beta.id, alpha.id, nil ])
    end

    it "accepts only asc or desc" do
      expect { described_class.by_workspace_name("asc; DROP TABLE users") }.to raise_error(ArgumentError)
    end
  end

  describe ".at_instance_level" do
    it "keeps only rows with no workspace" do
      grantee = create(:user)
      Operatorship.grant!(user: grantee)
      expect(described_class.at_instance_level.pluck(:workspace_id).uniq).to eq([ nil ])
      expect(described_class.at_instance_level.where(action: "operatorship.granted")).to exist
    end
  end
end
