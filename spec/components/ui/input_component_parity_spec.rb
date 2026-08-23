# frozen_string_literal: true

require "rails_helper"

# Parity gate: UI::InputComponent must render identically whether instantiated
# directly or through TailwindFormBuilder — the builder is a thin wrapper that
# delegates to this exact component (see app/form_builders/ui/form_builder.rb),
# so there is no separate `.form-field` class scheme to keep in sync anymore;
# the parity IS the shared component.
RSpec.describe UI::InputComponent, "field styling parity with TailwindFormBuilder", type: :component do
  include Capybara::RSpecMatchers

  let(:user) { User.new }
  let(:builder) { TailwindFormBuilder.new(:user, user, vc_test_controller.view_context, {}) }

  def parse(html)
    Capybara.string(html.to_s)
  end

  it "applies the same base chrome classes in normal state as the builder's text_field" do
    render_inline(described_class.new(name: "user[first_name]"))
    direct_class = page.find("input")[:class]

    builder_result = parse(builder.text_field(:first_name))
    builder_class = builder_result.find("input")[:class]

    expect(direct_class).to eq(builder_class)
  end

  it "applies the same error-state classes as the builder's text_field on an invalid field" do
    user.errors.add(:first_name, "can't be blank")

    render_inline(described_class.new(name: "user[first_name]", invalid: true))
    direct_class = page.find("input")[:class]

    builder_result = parse(builder.text_field(:first_name))
    builder_class = builder_result.find("input")[:class]

    expect(direct_class).to eq(builder_class)
    expect(direct_class).to include("border-danger")
  end
end
