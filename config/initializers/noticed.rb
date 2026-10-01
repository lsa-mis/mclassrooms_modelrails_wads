# frozen_string_literal: true

# Stamps dispatched_at as EventJob starts, so a lost enqueue can be re-sent (#927);
# raising jobs retry and may repeat an email (#1065). See /docs/developer/notifications.
Rails.application.config.to_prepare do
  # `to_prepare` runs on every reload in development, but `Noticed::EventJob`
  # lives in the gem's engine and is not reloaded with the app — registering
  # unconditionally would stack a duplicate callback per reload. The guard is
  # correct either way: a class that IS reloaded arrives without the ivar.
  unless Noticed::EventJob.instance_variable_get(:@dispatch_watermark_registered)
    Noticed::EventJob.instance_variable_set(:@dispatch_watermark_registered, true)

    Noticed::EventJob.before_perform do |job|
      job.arguments.first&.update_column(:dispatched_at, Time.current)
    end

    Noticed::EventJob.retry_on StandardError, wait: :polynomially_longer, attempts: 3
  end
end
