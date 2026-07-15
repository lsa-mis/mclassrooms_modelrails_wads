# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey enrollment prompt", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  it "shows the enrollment banner on an authenticated page, then never again once dismissed" do
    # The factory default stamps passkey_prompt_seen_at to suppress the banner;
    # reset to nil to make this user eligible.
    user.update!(passkey_prompt_seen_at: nil)
    get root_path
    expect(response.body).to include('id="passkey-banner"')
    patch passkey_prompt_path # dismiss (×) — stamps passkey_prompt_seen_at
    get root_path
    expect(response.body).not_to include('id="passkey-banner"')
  end

  it "does not show once the user already has a passkey (independent of seen_at)" do
    user.update!(passkey_prompt_seen_at: nil)
    create(:webauthn_credential, user: user)
    get root_path
    expect(response.body).not_to include('id="passkey-banner"')
  end

  it "renders the nudge message screen-reader-only on mobile so the banner is a one-line bar" do
    # 2026-07-15 panel: the full message wrapped to ~3 min-h-11 rows (~125px) on
    # a phone — the whole first screen. It's now sr-only on mobile (the icon +
    # the Add-a-passkey link carry the intent) and visible from sm up.
    user.update!(passkey_prompt_seen_at: nil)
    get root_path
    expect(response.body).to include('id="passkey-banner"')
    expect(response.body).to include("sr-only sm:not-sr-only")
  end
end
