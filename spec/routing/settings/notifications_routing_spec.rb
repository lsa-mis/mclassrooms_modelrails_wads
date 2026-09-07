# frozen_string_literal: true

require "rails_helper"

# Route absence is the only assertion that fails for exactly one reason: the
# route came back. (A 404 request spec also passes for a wrong id or a
# denied policy.) rails_helper infers type: :routing from this path.
RSpec.describe "settings/notifications routes" do
  it "no longer routes DELETE for a single notification" do
    expect(delete: "/settings/notifications/1").not_to be_routable
  end

  it "no longer routes DELETE destroy_all_read" do
    expect(delete: "/settings/notifications/destroy_all_read").not_to be_routable
  end

  it "still routes the read-state update" do
    expect(patch: "/settings/notifications/1").to route_to("settings/notifications#update", id: "1")
  end
end
