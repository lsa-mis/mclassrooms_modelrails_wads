# Rails writes a log line for a HANDLED report only when a subscriber raises, so
# without one the app's ten `Rails.error.report` sites reached nothing at all —
# not a tracker, not even the log. Every one of them is a deliberate best-effort
# rescue (the audit trail, the broadcast surfaces, the membership touch), and
# that trade is only sound if somebody can see the report (#1209).
#
# This is the floor, not a tracker: a fork wires Sentry/Honeybadger/etc. as a
# second subscriber and this one keeps doing its job alongside it.
#
# It must never raise. A raising subscriber would turn a swallowed error into a
# user-visible one, from inside the rescue that exists to prevent exactly that —
# and it would do it at every call site at once.
class ErrorLogSubscriber
  def report(error, handled:, severity:, context: {}, source: nil)
    Rails.logger.error(
      "[error_report] #{handled ? 'handled' : 'unhandled'} severity=#{severity} " \
      "source=#{source.presence || 'unknown'} #{error.class}: #{error.message} " \
      "context=#{context.inspect}"
    )
  rescue StandardError
    # A logger that cannot log is not worth an exception here.
    nil
  end
end

Rails.error.subscribe(ErrorLogSubscriber.new)
