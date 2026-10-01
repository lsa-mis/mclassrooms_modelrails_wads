# Notifier-spec helpers, defined once so a copy cannot drift (#1273).
module NoticedHelpers
  # Scoped, in sequence: each Noticed job enqueues the next; a bare drain runs the factory's CheckGravatarJob.
  # deliver_mail: also runs ActionMailer's job, without which a "sent no email" assertion passes vacuously.
  def drain_noticed_jobs(deliver_mail: false)
    perform_enqueued_jobs(only: Noticed::EventJob)
    perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) if deliver_mail
  end

  def notifier_events
    Noticed::Event.where(type: described_class.name)
  end
end

RSpec.configure do |config|
  config.include NoticedHelpers, type: :notifier
end
