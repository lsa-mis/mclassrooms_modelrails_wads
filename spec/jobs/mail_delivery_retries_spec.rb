# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Delivering mail from a job" do
  include ActiveJob::TestHelper

  def fail_transport_with(error)
    allow(Mail::TestMailer).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |transport| allow(transport).to receive(:deliver!).and_raise(error) }
    end
  end

  before { MagicLinkMailer.registration_link("ada@humbledaisy.com", "token").deliver_later }

  it "tries again when the server could not be reached, so a sign-in link is not lost" do
    fail_transport_with(Net::OpenTimeout)

    expect { perform_enqueued_jobs }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
  end

  it "retries a server that is busy or refusing connections" do
    [ Net::SMTPServerBusy.new(Net::SMTP::Response.parse("421 Try again later")), Errno::ECONNREFUSED ].each do |error|
      fail_transport_with(error)

      expect { perform_enqueued_jobs }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end
  end

  it "fails the job instead of retrying a send the server may already have accepted" do
    fail_transport_with(Net::ReadTimeout)

    expect { perform_enqueued_jobs }.to raise_error(Net::ReadTimeout)
    expect(enqueued_jobs).to be_empty
  end
end
