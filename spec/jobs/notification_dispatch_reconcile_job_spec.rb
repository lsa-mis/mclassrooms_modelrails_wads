# frozen_string_literal: true

require "rails_helper"

# #927. The recovery half of the dispatch watermark: an event whose rows
# committed but whose `Noticed::EventJob` never landed carries no
# `dispatched_at`, and after a grace window this sweep re-enqueues it.
RSpec.describe NotificationDispatchReconcileJob, type: :job do
  let(:user) { create(:user) }

  # `enqueue_job: false` is noticed's own switch for "write the rows, skip the
  # enqueue" — exactly the state a lost enqueue leaves behind, and it keeps the
  # setup out of the block the matcher measures.
  def undispatched_event(age: 10.minutes)
    WelcomeNotifier.with(record: user).deliver(user, enqueue_job: false)
    Noticed::Event.where(type: "WelcomeNotifier").last.tap do |event|
      event.update_columns(created_at: age.ago)
    end
  end

  # `low` is chartered as "nobody is waiting on it"; a recovered notification is
  # a notification someone is waiting on, and it must not queue behind an hour
  # of blob purges. Same reasoning that keeps the two workspace sweeps on
  # `default`.
  it "runs on the default queue" do
    expect(described_class.queue_name).to eq("default")
  end

  it "re-enqueues an event that was never stamped and is past the grace window" do
    event = undispatched_event

    expect { described_class.perform_now }
      .to have_enqueued_job(Noticed::EventJob).with(event).exactly(:once)
  end

  # The row shape every event carried before this release, and the shape of any
  # event that is permanently unstampable. Without a lookback bound the sweep
  # re-enqueues them every cycle, forever.
  it "leaves an unstamped row older than the lookback window alone" do
    undispatched_event(age: 3.weeks)

    expect { described_class.perform_now }.not_to have_enqueued_job(Noticed::EventJob)
  end

  # If the delivery queue backs up past the 15-minute cadence, cycle N+1 finds
  # the same still-unstamped event. The sweep's own stamp is what stops that
  # from fanning a second copy of every email out to every recipient.
  it "re-enqueues an event once, not once per cycle" do
    event = undispatched_event

    expect {
      described_class.perform_now
      described_class.perform_now
    }.to have_enqueued_job(Noticed::EventJob).with(event).exactly(:once)
  end

  it "leaves an unstamped event inside the grace window alone" do
    undispatched_event(age: 1.minute)

    expect { described_class.perform_now }.not_to have_enqueued_job(Noticed::EventJob)
  end

  it "leaves an already-dispatched event alone" do
    undispatched_event.update_column(:dispatched_at, Time.current)

    expect { described_class.perform_now }.not_to have_enqueued_job(Noticed::EventJob)
  end

  it "skips an event that reached nobody (#928)" do
    undispatched_event.update_column(:notifications_count, 0)

    expect { described_class.perform_now }.not_to have_enqueued_job(Noticed::EventJob)
  end

  it "re-raises when every attempted re-enqueue failed, so Solid Queue records a failure" do
    undispatched_event
    allow(Noticed::EventJob).to receive(:perform_later).and_raise(RuntimeError, "queue database is locked")

    expect { described_class.perform_now }.to raise_error(RuntimeError, "queue database is locked")
  end

  # The issue's own scenario, end to end: the enqueue fails AFTER noticed's
  # transaction committed, so the recipient can see the notification, the
  # idempotency key is burned (a retry inside the bucket would dedup away), and
  # the email and broadcast legs never ran.
  describe "the #927 scenario" do
    it "recovers an event whose enqueue raised after the rows committed" do
      configured = instance_double(ActiveJob::ConfiguredJob)
      allow(Noticed::EventJob).to receive(:set).and_return(configured)
      allow(configured).to receive(:perform_later)
        .and_raise(ActiveRecord::StatementInvalid, "database is locked")

      expect { WelcomeNotifier.with(record: user).deliver(user) }
        .to raise_error(ActiveRecord::StatementInvalid)

      event = Noticed::Event.where(type: "WelcomeNotifier").last
      expect(event.idempotency_key).to be_present
      expect(event.notifications.count).to eq(1)
      expect(event.dispatched_at).to be_nil

      travel 6.minutes do
        expect { described_class.perform_now }
          .to have_enqueued_job(Noticed::EventJob).with(event).exactly(:once)
      end
    end
  end
end
