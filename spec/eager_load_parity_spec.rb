require "rails_helper"

# A green local run is CI evidence only if both run the same program (#852):
# eager_load was `ENV["CI"].present?`, so Zeitwerk's load order — and every
# `descendants`, ObjectSpace, subscriber-registration, and class-body side
# effect downstream of it — differed between the Lefthook pre-push gate and
# CI. Lives at spec root beside the other harness contracts.
RSpec.describe "test-environment eager loading" do
  it "eager-loads exactly as CI does" do
    expect(Rails.application.config.eager_load).to be(true)
  end
end
