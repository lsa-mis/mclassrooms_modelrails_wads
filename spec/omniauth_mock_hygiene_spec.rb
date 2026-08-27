require "rails_helper"

# Self-test for spec/support/omniauth_helpers.rb (#851): the after-example
# cleanup must RESTORE the pristine mock_auth — including the :default
# AuthHash OmniAuth ships — not destroy it. The old cleanup nilled every key,
# so whether an example saw mock_auth[:default] depended on whether any
# OmniAuth example had run before it in that worker: pure order dependence.
#
# `order: :defined` on purpose — the pair IS an ordering: the first example
# plays the OmniAuth spec, the second proves the cleanup left pristine state.
# Lives at spec root beside factory_contracts_spec.rb (harness contracts).
RSpec.describe "OmniAuth mock_auth hygiene", order: :defined do
  it "an example can mock a provider" do
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(provider: "github", uid: "hygiene-probe")

    expect(OmniAuth.config.mock_auth[:github].uid).to eq("hygiene-probe")
  end

  it "the next example sees the pristine state again" do
    expect(OmniAuth.config.mock_auth[:default]).to be_an(OmniAuth::AuthHash)
    expect(OmniAuth.config.mock_auth).not_to have_key(:github)
  end
end
