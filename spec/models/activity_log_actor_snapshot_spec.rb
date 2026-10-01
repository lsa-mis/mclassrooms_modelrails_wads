require "rails_helper"

# An audit row outlives its actor: a name snapshot replaces the actor_id FK (#1122).
RSpec.describe "ActivityLog actor snapshot" do
  let(:actor) { create(:user, first_name: "Dana", last_name: "Ruiz") }
  let(:workspace) { actor.workspaces.sole }

  describe "at write time" do
    it "records the actor's name on the row" do
      log = acting_as(actor, workspace: actor.workspaces.sole) { workspace.update!(name: "Renamed"); workspace.activities.last }

      expect(log.actor_name).to eq("Dana Ruiz")
    end

    # Derived, never caller-supplied (#1250).
    it "refuses a snapshot supplied by the caller" do
      dana = create(:user, first_name: "Dana", last_name: "Ruiz")

      log = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                actor: dana, workspace: workspace,
                                actor_name: "Someone Else")

      expect(log.reload.actor_name).to eq("Dana Ruiz")
    end

    # "" used to slip past a `.nil?` guard and read back as departed.
    it "overwrites an empty snapshot rather than reading it back as departed" do
      dana = create(:user, first_name: "Dana", last_name: "Ruiz")

      log = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                actor: dana, workspace: workspace, actor_name: "")

      expect(log.reload.display_subject).to eq("Dana Ruiz")
    end

    it "leaves the snapshot blank when there is no actor" do
      log = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                actor: nil, workspace: workspace)

      expect(log.actor_name).to be_nil
    end

    it "does not follow the actor's later rename" do
      log = acting_as(actor, workspace: actor.workspaces.sole) { workspace.update!(name: "Renamed"); workspace.activities.last }

      actor.update!(first_name: "Dee", last_name: "Ruiz")

      expect(log.reload.display_subject).to eq("Dana Ruiz")
    end
  end

  describe "after the actor is gone" do
    # Only that this table stopped blocking deletion; five other FKs still do (#1248).
    it "stops being a reason the actor cannot be destroyed" do
      acting_as(actor, workspace: actor.workspaces.sole) { workspace.update!(name: "Renamed") }
      expect(ActivityLog.where(actor_id: actor.id)).to be_any

      expect { actor.destroy! }.not_to raise_error
    end

    it "still names who acted" do
      log = acting_as(actor, workspace: actor.workspaces.sole) { workspace.update!(name: "Renamed"); workspace.activities.last }
      actor.destroy!

      expect(log.reload.display_subject).to eq("Dana Ruiz")
    end

    # A person did this, so a departed actor is never "System".
    it "distinguishes a departed actor from no actor at all" do
      orphan = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                   actor: actor, workspace: workspace)
      # Raw SQL: readonly? refuses update_columns; only a legacy row is blank.
      ActiveRecord::Base.connection.execute(
        "UPDATE activity_logs SET actor_name = NULL WHERE id = #{orphan.id}"
      )
      actor.destroy!

      expect(orphan.reload.display_subject).to eq(I18n.t("activity.departed_actor"))
    end

    # A pre-snapshot row with a living actor resolves live, so it follows a rename.
    it "resolves a pre-snapshot row through its living actor" do
      log = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                actor: actor, workspace: workspace)
      ActiveRecord::Base.connection.execute(
        "UPDATE activity_logs SET actor_name = NULL WHERE id = #{log.id}"
      )

      expect(log.reload.display_subject).to eq("Dana Ruiz")

      actor.update!(first_name: "Dee")
      expect(log.reload.display_subject).to eq("Dee Ruiz")
    end

    it "reports no subject at all when the row never had an actor" do
      log = ActivityLog.create!(action: "workspace.updated", trackable: workspace,
                                actor: nil, workspace: workspace)

      expect(log.display_subject).to be_nil
    end
  end

  # Both columns fail the same way (#1122).
  it "keeps actor_id and trackable_id consistently free of foreign keys" do
    fks = ActiveRecord::Base.connection.foreign_keys("activity_logs").map(&:column)

    # POSITIVE CONTROL: absences also pass on an empty list.
    expect(fks).to include("workspace_id"),
      "the foreign-key reader returned nothing useful, so the two absences below prove nothing"

    expect(fks).not_to include("actor_id"),
      "actor_id regained a FK, so a departed actor blocks user deletion again (#1122)"
    expect(fks).not_to include("trackable_id"),
      "trackable_id is polymorphic and cannot carry a FK"
  end
end
