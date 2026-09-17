# frozen_string_literal: true

require "rails_helper"

# The dispatch watermark (#927). noticed commits the event and its notification
# rows in one transaction and enqueues `EventJob` AFTER that transaction
# returns, so an enqueue that never lands — a process death in the gap, or
# Solid Queue's own database busy past its timeout — leaves rows the recipient
# can see in the bell with no email and no broadcast behind them.
#
# `dispatched_at` is stamped at the START of the job, on purpose: a job that
# was CLAIMED is Solid Queue's to retry under its own policy, so the reconciler
# covers only the never-enqueued gap and can never double-send an event whose
# delivery legs already fanned out.
RSpec.describe Noticed::EventJob, type: :job do
  let(:user) { create(:user) }

  def welcome_event
    WelcomeNotifier.with(record: user).deliver(user)
    Noticed::Event.where(type: "WelcomeNotifier").last
  end

  it "leaves dispatched_at nil while the job is only enqueued" do
    expect(welcome_event.dispatched_at).to be_nil
  end

  it "stamps dispatched_at when the job performs" do
    event = welcome_event

    freeze_time do
      described_class.perform_now(event)
      expect(event.reload.dispatched_at).to eq(Time.current)
    end
  end

  it "stamps dispatched_at before delivering, so a raising leg still marks the event dispatched" do
    event = welcome_event
    allow(event).to receive(:bulk_delivery_methods).and_raise(RuntimeError, "delivery exploded")

    expect { described_class.perform_now(event) }.to raise_error(RuntimeError, "delivery exploded")
    expect(event.reload.dispatched_at).to be_present
  end
end
