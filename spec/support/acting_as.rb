# frozen_string_literal: true

# Current.user is derived from the session and not assignable, so a spec that
# needs an actor signs one in the way a request does. Sets the workspace only when asked.
module ActingAs
  def acting_as(user, workspace: nil)
    Current.session = user.sessions.create!(user_agent: "spec", ip_address: "127.0.0.1")
    Current.workspace = workspace if workspace
    yield
  ensure
    Current.session = nil
    Current.workspace = nil if workspace
  end
end

RSpec.configure do |config|
  config.include ActingAs
end
