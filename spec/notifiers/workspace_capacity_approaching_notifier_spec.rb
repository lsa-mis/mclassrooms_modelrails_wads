# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceCapacityApproachingNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  def capacity_cast
    owner_a = create(:user)
    owner_b = create(:user)
    non_owner = create(:user)
    workspace = create(:workspace)
    create(:membership, :owner, user: owner_a, workspace: workspace)
    create(:membership, :owner, user: owner_b, workspace: workspace)
    create(:membership, user: non_owner, workspace: workspace)
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    { workspace: workspace, owner_a: owner_a, owner_b: owner_b, non_owner: non_owner }
  end

  describe ".category" do
    it "is :billing" do
      expect(described_class.category_name).to eq "billing"
    end

    it "is NOT a security category notifier (does not bypass DND)" do
      expect(ApplicationNotifier.notifier_class_names_for("security")).not_to include(described_class.name)
    end
  end

  # Recipient resolution itself is asserted through the real dispatch under
  # "dispatching" below (a row for each owner, none for the non-owner) — the
  # public surface says the same thing, so there is no resolver example here.
  describe "recipient resolution query efficiency" do
    it "issues exactly one user_preferences query for N owners (preloaded, not N+1)" do
      workspace = capacity_cast.fetch(:workspace)
      # A third owner so an N+1 (one user_preferences query per owner) diverges
      # loudly from the single preloaded query the contract requires.
      owner_c = create(:user)
      create(:membership, :owner, user: owner_c, workspace: workspace)

      event = described_class.with(record: workspace, metric: "members", current: 8, limit: 10)

      # evaluate_recipients is public API on Noticed::Deliverable — it needs
      # no `send`, and calling it keeps THIS notifier's recipients block in
      # the measurement. Measuring `permitted_in_app` directly instead would
      # still count one query after a refactor that stopped preloading here.
      query_count = count_queries_touching("user_preferences") do
        event.evaluate_recipients
      end

      expect(query_count).to eq 1
    end
  end

  # #936. The recipients block above is leg A, and it is flat. This is leg B:
  # Noticed's EventJob iterates `event.notifications.each` and runs this
  # notifier's email `before_enqueue` against every row — and this notifier's
  # email leg has NO narrowing guard, so the gate is genuinely asked about each
  # recipient. Read off the notification row that means a cold `recipient`
  # load plus a `preferences` load per owner: eight and eight at eight owners.
  #
  # Two scoped counts rather than one total: a total-equality assertion can be
  # satisfied by luck — one leg shrinking while another grows.
  describe "email gate cost across the fan-out" do
    def event_for_workspace_with(owner_count)
      fanned_out = create(:workspace, max_members: 60)
      owner_count.times do
        create(:membership, :owner, user: create(:user), workspace: fanned_out)
      end
      described_class.with(record: fanned_out, metric: "members", current: 8, limit: 10).deliver(nil)
      Noticed::Event.where(type: described_class.name).order(:created_at).last
    end

    # Each measurement re-finds the event so the second one starts from a cold
    # instance: measuring twice against one in-memory event would read the
    # first run's memo and report a query count no cold job ever pays.
    def queries_touching(table, event_id)
      count_queries_touching(table) { Noticed::EventJob.perform_now(Noticed::Event.find(event_id)) }
    end

    it "loads the recipients and their preferences once each, not once per owner" do
      event_id = event_for_workspace_with(8).id

      aggregate_failures do
        expect(queries_touching("users", event_id)).to eq 1
        expect(queries_touching("user_preferences", event_id)).to eq 1
      end
    end
  end

  describe "dispatching" do
    it "delivers in-app notifications to all owners under default preferences" do
      workspace, owner_a, owner_b, non_owner = capacity_cast.values_at(:workspace, :owner_a, :owner_b, :non_owner)
      result = described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      expect(result).to eq :delivered
      expect(Noticed::Notification.where(recipient: owner_a, type: "#{described_class.name}::Notification").count).to eq 1
      expect(Noticed::Notification.where(recipient: owner_b, type: "#{described_class.name}::Notification").count).to eq 1
      expect(Noticed::Notification.where(recipient: non_owner, type: "#{described_class.name}::Notification").count).to eq 0
    end

    it "auto-populates idempotency_key on the event column" do
      workspace = capacity_cast.fetch(:workspace)
      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "enqueues NotificationMailer.workspace_capacity_approaching for each owner under default preferences" do
      workspace = capacity_cast.fetch(:workspace)
      expect {
        described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_capacity_approaching).twice
    end

    it "creates exactly one Noticed::Event row per dispatch (regardless of recipient count)" do
      workspace = capacity_cast.fetch(:workspace)
      expect {
        described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
    end
  end

  describe "day-bucket idempotency" do
    it "deduplicates two consecutive dispatches within the same day for the same (workspace, metric)" do
      workspace = capacity_cast.fetch(:workspace)
      freeze_time do
        first = described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
        second = described_class.with(record: workspace, metric: "members", current: 9, limit: 10).deliver(nil)
        expect(first).to eq :delivered
        expect(second).to eq :deduplicated
      end
    end

    it "delivers a fresh dispatch the next day" do
      workspace = capacity_cast.fetch(:workspace)
      now = Time.current
      travel_to(now) do
        described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      end

      travel_to(now + 1.day) do
        result = described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
        expect(result).to eq :delivered
      end
    end

    it "does not deduplicate across distinct metrics on the same day" do
      workspace = capacity_cast.fetch(:workspace)
      freeze_time do
        members = described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
        projects = described_class.with(record: workspace, metric: "projects", current: 4, limit: 5).deliver(nil)
        expect(members).to eq :delivered
        expect(projects).to eq :delivered
      end
    end
  end

  describe "preference gating" do
    it "suppresses both in-app and email under DND for that owner (billing does NOT bypass)" do
      workspace, owner_a, owner_b = capacity_cast.values_at(:workspace, :owner_a, :owner_b)
      prefs = create(:user_preferences, user: owner_a)
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))

      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      drain_noticed_jobs

      expect(Noticed::Notification.where(recipient: owner_a,
                                          type: "#{described_class.name}::Notification").count).to eq 0
      # owner_b unaffected
      expect(Noticed::Notification.where(recipient: owner_b,
                                          type: "#{described_class.name}::Notification").count).to eq 1
    end

    it "fires in-app but skips email when the email channel is disabled" do
      workspace, owner_a = capacity_cast.values_at(:workspace, :owner_a)
      prefs = create(:user_preferences, user: owner_a)
      delivery_methods = prefs.notification_preferences["delivery_methods"].deep_dup
      delivery_methods["email"]["enabled"] = false
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("delivery_methods" => delivery_methods))

      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)

      notification = Noticed::Notification.find_by(recipient: owner_a, type: "#{described_class.name}::Notification")
      expect(notification).not_to be_nil
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be false
    end
  end

  describe "#message" do
    it "renders the localized capacity-approaching message with workspace, metric, current and limit" do
      workspace, owner_a = capacity_cast.values_at(:workspace, :owner_a)
      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      notification = Noticed::Notification.find_by(recipient: owner_a, type: "#{described_class.name}::Notification")
      expect(notification.message).to eq(
        I18n.t("notifications.workspace_capacity_approaching.message",
               workspace_name: workspace.name,
               metric: "members",
               current: 8,
               limit: 10)
      )
    end
  end
  # #920. The row outlives the workspace it points at, and #url may not raise
  # out of the notifications index or the digest render — the digest wraps
  # RENDERING, not URL generation, so one stale row takes down a whole
  # recipient's digest rather than just its own line.
  describe "#url once the workspace is gone" do
    it "renders the placeholder instead of raising" do
      workspace = capacity_cast.fetch(:workspace)
      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      notification = Noticed::Event.where(type: described_class.name).last.notifications.first
      workspace.destroy!

      expect(notification.reload.url).to eq(I18n.t("notifications.placeholder"))
    end
  end
end
