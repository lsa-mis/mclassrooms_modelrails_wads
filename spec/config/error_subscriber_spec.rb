require "rails_helper"

# Ten call sites across nine files report handled errors. Rails only writes a log
# line for a handled report when a subscriber raises, so with no subscriber
# registered those reports reached nothing at all — not a tracker, not even the
# log. Every one of those sites is a deliberate best-effort rescue, and that
# trade is only sound if the report is observable somewhere (#1209).
RSpec.describe "Handled error reports" do
  let(:logged) { StringIO.new }

  around do |example|
    previous = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(logged))
    example.run
  ensure
    Rails.logger = previous
  end

  it "reach the log, with their context and source" do
    Rails.error.report(
      ArgumentError.new("boom"),
      handled: true,
      source: "spec.error_subscriber",
      context: { workspace_id: 42 }
    )

    output = logged.string
    expect(output).to include("ArgumentError"), "the exception class is missing from the log line"
    expect(output).to include("boom"), "the message is missing"
    expect(output).to include("spec.error_subscriber"), "the source tag is missing"
    expect(output).to include("workspace_id"), "the context is missing"
  end

  it "distinguishes an unhandled report" do
    Rails.error.report(RuntimeError.new("fatal"), handled: false, source: "spec.error_subscriber")

    expect(logged.string).to match(/unhandled/i),
      "an unhandled report reads the same as a handled one, so severity is unreadable"
  end

  # The point of every rescue behind these reports is that the user's request
  # survives. A subscriber that raises would invert that — turning a swallowed
  # error into a visible one, from inside the rescue meant to prevent it.
  it "never lets a reporting failure escape to the caller" do
    allow(Rails.logger).to receive(:error).and_raise(IOError, "log device went away")

    expect {
      Rails.error.report(ArgumentError.new("boom"), handled: true, source: "spec.error_subscriber")
    }.not_to raise_error
  end
end
