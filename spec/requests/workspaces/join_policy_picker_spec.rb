require "rails_helper"

# The join-policy picker was two hand-rolled `f.radio_button` calls — the only
# field on this form that never passed through the design system (#738). It is
# now UI::RadioGroup, which is what #738 was blocked on: the component gained a
# per-item `description:` in modelrails_ui 0.20.0.
#
# What these examples protect is the reason the swap was worth making. The old
# markup put each option's help text, and the disabled explanation, INSIDE the
# `<label>` — so both became part of the radio's accessible name and were
# announced as the option itself ("Open link Anyone with the link can join This
# is unavailable because…"). A supporting line belongs in the description, read
# after the name. Nothing asserted any of this before, which is how two loose
# radios with no group name survived this long.
RSpec.describe "Workspace settings — join-policy picker", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  def doc
    get edit_workspace_settings_path(workspace)
    Capybara::Node::Simple.new(response.body)
  end

  def t(key) = I18n.t("workspaces.settings.join_policy.#{key}")

  def radio(page, value)
    page.find("input[type=radio][value='#{value}']", visible: :all)
  end

  # Opting the instance in, the way an operator does with
  # SIGNUP_PERMITTED_JOIN_STRATEGIES. Stubbed at the policy rather than the
  # config so the model's own validation sees the same answer the view does.
  #
  # BOTH spellings, deliberately: the view asks with the symbol `:open_link`,
  # while Workspace#join_policy_must_be_permitted_by_instance asks with the
  # attribute, a String. `permits_strategy?` coerces internally, so the two
  # callers are equivalent in production — but a stub matches the argument as
  # passed, so a symbol-only stub leaves the validation rejecting the value and
  # the save silently keeps "invite".
  def permit_open_link
    allow(SignupPolicy).to receive(:permits_strategy?).and_call_original
    allow(SignupPolicy).to receive(:permits_strategy?).with(:open_link).and_return(true)
    allow(SignupPolicy).to receive(:permits_strategy?).with("open_link").and_return(true)
  end

  it "wraps the options in a named group" do
    page = doc
    group = page.find("[role=radiogroup]", visible: :all)

    named_by = group["aria-labelledby"]
    expect(named_by).to be_present, "the radio group must carry an accessible name"
    expect(page).to have_css("[id='#{named_by}']", text: t("heading"), visible: :all)
  end

  it "describes each option rather than folding its help into the name" do
    page = doc
    invite = radio(page, "invite")

    described_by = invite["aria-describedby"]
    expect(described_by).to be_present, "each option must point at its supporting line"
    expect(page).to have_css("[id='#{described_by}']", text: t("invite_help"), visible: :all)

    # The load-bearing half: inside the label, the help becomes the radio's name.
    label = page.find("label[for='#{invite["id"]}']", visible: :all)
    expect(label.text).to include(t("invite_label"))
    expect(label.text).not_to include(t("invite_help"))
  end

  it "keeps every option's label at the 44px target floor" do
    page = doc

    expect(page).to have_css("[role=radiogroup] label.min-h-input", count: 2, visible: :all)
  end

  it "posts the chosen policy under the name the controller reads" do
    permit_open_link
    patch workspace_settings_path(workspace), params: { workspace: { join_policy: "open_link" } }

    expect(workspace.reload.join_policy).to eq("open_link")
  end

  # `permitted_join_strategies` defaults to [:invite] (config/application.rb),
  # so an instance that has NOT opted into open_link is the default state here,
  # not the exception — and Workspace#join_policy_must_be_permitted_by_instance
  # rejects the value even if the disabled control were bypassed.
  context "when the open-link strategy is not permitted (the default)" do
    it "disables that option and explains why in its description, not its name" do
      page = doc
      open_link = radio(page, "open_link")

      expect(open_link).to be_disabled

      described_by = open_link["aria-describedby"]
      expect(described_by).to be_present
      expect(page).to have_css("[id='#{described_by}']", text: t("open_link_disabled_explanation"), visible: :all)

      label = page.find("label[for='#{open_link["id"]}']", visible: :all)
      expect(label.text).not_to include(t("open_link_disabled_explanation"))
    end

    it "still offers invite, enabled" do
      page = doc

      expect(radio(page, "invite")).not_to be_disabled
    end
  end

  context "when the operator has opted the instance into open link" do
    before { permit_open_link }

    it "leaves the option enabled and says nothing about it being unavailable" do
      page = doc

      expect(radio(page, "open_link")).not_to be_disabled
      expect(page).to have_no_text(t("open_link_disabled_explanation"))
    end
  end
end
