require "rails_helper"

RSpec.describe "Settings::Passkeys", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  it "lists the user's kept passkeys" do
    create(:webauthn_credential, user: user, nickname: "My Laptop")
    get settings_passkeys_path
    expect(response.body).to include("My Laptop")
  end

  it "soft-discards a passkey on destroy (magic-link remains the floor)" do
    cred = create(:webauthn_credential, user: user)
    delete settings_passkey_path(cred)
    expect(cred.reload).to be_discarded
    expect(flash[:notice]).to eq(I18n.t("settings.passkeys.destroy.success"))
  end

  it "renders the Add a passkey control" do
    get settings_passkeys_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('[data-controller~="webauthn"]')).to be_present
    expect(doc.at_css('[data-action~="webauthn#register"]')).to be_present
  end

  it "renders remove aria-label for each credential" do
    create(:webauthn_credential, user: user, nickname: "Touch ID")
    get settings_passkeys_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('[aria-label="Remove passkey: Touch ID"]')).to be_present
  end

  it "wires the remove control to a modal controller so the confirm dialog opens" do
    # Regression: the remove trigger fired modal#open but had no
    # data-controller="modal" ancestor, so the click was a no-op and the passkey
    # could never be removed. The trigger AND the confirm <dialog> must share a
    # modal controller scope (the controller opens its own dialogTarget).
    create(:webauthn_credential, user: user, nickname: "Touch ID")
    get settings_passkeys_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('[data-controller~="modal"] [data-action~="click->modal#open"]')).to be_present
    expect(doc.at_css('[data-controller~="modal"] dialog')).to be_present
  end

  it "is reachable from the settings sidebar (not an orphaned page)" do
    # Regression: the passkeys page existed but no nav linked to it, so once the
    # one-time enrollment nudge was dismissed there was no way to add a
    # passkey. Assert the identity settings sidebar links to it from another page.
    get edit_settings_profile_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("a[href='#{settings_passkeys_path}']")).to be_present
  end

  it "rejects cross-user passkey deletion and leaves the credential intact (IDOR)" do
    # The controller scopes destroy via Current.user.webauthn_credentials so
    # a foreign credential ID raises RecordNotFound. The HTML handler for
    # RecordNotFound redirects (not 404) to preserve UX consistency — assert
    # the redirect AND that the credential was not discarded.
    other_user = create(:user)
    other_cred = create(:webauthn_credential, user: other_user)

    delete settings_passkey_path(other_cred)

    expect(response).to be_redirect
    expect(other_cred.reload.discarded_at).to be_nil
  end
end
