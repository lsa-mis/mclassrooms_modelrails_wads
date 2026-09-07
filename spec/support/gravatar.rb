# CheckGravatarJob is enqueued by every user create/email-change (#914) and
# hits the real gravatar.com over Net::HTTP. Its rescue only catches
# StandardError, but WebMock's disallowed-connection error is a bare
# Exception, so a bare perform_enqueued_jobs blew up regardless of whether the
# spec under test was correct. Default every lookup to "no gravatar" so the
# job is inert unless a spec deliberately registers its own stub_request for
# this host, which takes precedence.
RSpec.configure do |config|
  config.before do
    stub_request(:head, %r{\Ahttps://www\.gravatar\.com/avatar/}).to_return(status: 404)
  end
end
