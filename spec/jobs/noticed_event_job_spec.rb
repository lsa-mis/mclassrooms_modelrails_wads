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
  include ActiveJob::TestHelper

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

  # A claimed job that raises is stamped, so only retry_on can recover it (#1065).
  it "retries a raising delivery instead of parking the event after one attempt" do
    event = welcome_event
    attempts = 0
    allow_any_instance_of(Noticed::Event).to receive(:bulk_delivery_methods) do
      attempts += 1
      raise "transient delivery fault" if attempts == 1

      {}
    end

    perform_enqueued_jobs { described_class.perform_later(event) }

    expect(attempts).to eq(2),
      "the job gave up after #{attempts} attempt(s) — a transient fault parks the event in " \
      "failed executions, where nothing in this app will find it"
  end

  # The stamp lands before the legs run; retry_on now catches the raise (#1065).
  it "stamps dispatched_at before delivering, so a raising leg still marks the event dispatched" do
    event = welcome_event
    allow(event).to receive(:bulk_delivery_methods).and_raise(RuntimeError, "delivery exploded")

    described_class.perform_now(event)

    expect(event.reload.dispatched_at).to be_present
  end
end
