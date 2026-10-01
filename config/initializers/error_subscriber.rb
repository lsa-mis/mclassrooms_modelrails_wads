# Logs handled Rails.error reports, which otherwise reach nothing; never raises (#1209).
# Adding a tracker reopens the token-in-path decision: /docs/developer/security.
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
