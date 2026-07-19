require "rails_helper"

RSpec.describe FeedbackPolicy do
  let(:user) { create(:user) }

  it "allows any authenticated user to open and submit the feedback form" do
    policy = described_class.new(user, :feedback)

    expect(policy.new?).to be true
    expect(policy.create?).to be true
  end
end
