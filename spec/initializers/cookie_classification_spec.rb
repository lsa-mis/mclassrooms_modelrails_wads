# frozen_string_literal: true

require "rails_helper"

# #714: every cookie the app itself sets is classified once, next to Biscuit's
# consent categories, and the docs list the same set. A new cookie must land
# in both, with its category and reason.
RSpec.describe "Cookie classification" do
  let(:classification) { Rails.application.config.cookie_classification }
  let(:doc) { File.read(Rails.root.join("app/docs/developer/security.md")) }

  it "classifies exactly the cookies the app sets" do
    # session_id is the app's own signed cookie (Authenticatable); Rails' own
    # cookie-store session (flash, CSRF, pending-join/invitation tokens) rides
    # under a different name — the app's configured key — so it gets its own
    # entry rather than being folded into session_id.
    rails_session_cookie = Rails.application.config.session_options[:key].to_sym

    expect(classification.keys).to contain_exactly(
      :session_id, rails_session_cookie, :biscuit_consent, :theme, :sidebar_collapsed
    )
    expect(classification.values.map { |v| v.fetch(:category) }.uniq).to eq([ :necessary ])
    classification.each_value { |v| expect(v.fetch(:reason)).to be_present }
  end

  it "is mirrored in the security doc" do
    classification.each_key { |name| expect(doc).to include("`#{name}`") }
  end
end
