require "rails_helper"

# TailwindFormBuilder is the app's fork seam over UI::FormBuilder (see the class
# comment) — these specs instantiate TailwindFormBuilder directly (not the gem
# class) to prove the seam passes every contract through untouched. Assertions
# mirror modelrails_ui's own render tests
# (test/render/form_builder_render_test.rb) in RSpec idiom rather than
# inventing new contracts.
RSpec.describe TailwindFormBuilder, type: :component do
  include Capybara::RSpecMatchers

  let(:user) { User.new }
  let(:builder) { described_class.new(:user, user, vc_test_controller.view_context, {}) }

  def parse(html)
    Capybara.string(html.to_s)
  end

  describe "#text_field" do
    it "binds the label, the control, and its id together" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("label[for='user_first_name']", text: "First name")
      expect(result).to have_css("[data-slot='control'] input#user_first_name[type='text'][name='user[first_name]']")
    end

    it "uses custom label text when provided" do
      result = parse(builder.text_field(:first_name, label: "Your Name"))
      expect(result).to have_css("label", text: "Your Name")
    end

    it "renders a hint below the control, wired via aria-describedby" do
      result = parse(builder.text_field(:first_name, help: "Enter your first name"))
      expect(result).to have_css("p#user_first_name-hint", text: "Enter your first name")
      expect(result).to have_css("input[aria-describedby='user_first_name-hint']")
    end

    it "merges custom classes" do
      result = parse(builder.text_field(:first_name, class: "w-1/2"))
      expect(result).to have_css("input.w-1\\/2")
    end

    it "passes through HTML attributes" do
      result = parse(builder.text_field(:first_name, autofocus: true, autocomplete: "given-name"))
      expect(result).to have_css("input[autofocus][autocomplete='given-name']")
    end
  end

  describe "#text_field with errors" do
    before { user.errors.add(:first_name, "can't be blank") }

    it "sets aria-invalid on the input" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("input[aria-invalid='true']")
    end

    it "renders the error as a plain paragraph — no role=alert (the summary is the live region)" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("p#user_first_name-error", text: "can't be blank")
      expect(result).not_to have_css("p#user_first_name-error[role='alert']")
    end

    it "orders aria-describedby error-first, then hint" do
      result = parse(builder.text_field(:first_name, help: "h"))
      expect(result).to have_css("input[aria-describedby='user_first_name-error user_first_name-hint']")
    end
  end

  describe "#email_field" do
    it "renders email input type" do
      result = parse(builder.email_field(:email_address))
      expect(result).to have_css("input[type='email']")
    end
  end

  describe "#password_field" do
    it "renders password input type" do
      result = parse(builder.password_field(:password))
      expect(result).to have_css("input[type='password']")
    end

    it "defaults to autocomplete new-password" do
      result = parse(builder.password_field(:password))
      expect(result).to have_css("input[autocomplete='new-password']")
    end

    it "allows overriding autocomplete" do
      result = parse(builder.password_field(:password, autocomplete: "current-password"))
      expect(result).to have_css("input[autocomplete='current-password']")
    end
  end

  describe "#text_area" do
    it "renders a textarea" do
      result = parse(builder.text_area(:first_name))
      expect(result).to have_css("textarea")
    end

    it "defaults to 4 rows" do
      result = parse(builder.text_area(:first_name))
      expect(result).to have_css("textarea[rows='4']")
    end

    it "allows custom rows" do
      result = parse(builder.text_area(:first_name, rows: 8))
      expect(result).to have_css("textarea[rows='8']")
    end
  end

  describe "#select" do
    it "renders a select with options and a label" do
      result = parse(builder.select(:first_name, [ [ "Admin", "admin" ], [ "Member", "member" ] ], label: "Role"))
      expect(result).to have_css("select")
      expect(result).to have_css("option", text: "Admin")
      expect(result).to have_css("label", text: "Role")
    end

    # The customizable-select picker styling keys off `.ui-select` (see
    # modelrails_ui.css `@supports (appearance: base-select)`). App dropdowns are
    # native form-builder selects, so the hook must ride on `f.select` directly.
    # The old `.form-field` phantom class is gone — chrome now comes from the
    # gem's SelectComponent::BASE, applied via `f.select`, not a host-only class.
    it "carries the `ui-select` hook and the gem's select chrome, not the old form-field class" do
      result = parse(builder.select(:first_name, [ [ "Admin", "admin" ] ], label: "Role"))
      expect(result).to have_css("select.ui-select")
      expect(result).not_to have_css("select.form-field")
    end

    it "is aria-required only, never native required" do
      result = parse(builder.select(:first_name, %w[a b], required: true))
      expect(result).to have_css("select[aria-required='true']")
      expect(result).not_to have_css("select[required]")
    end

    it "honours caller html_options" do
      result = parse(builder.select(:first_name, %w[a b], {}, { "data-controller" => "auto-submit" }))
      expect(result).to have_css("select[data-controller='auto-submit']")
    end

    # v0.13.0 contract fix (gem #145): required in the DOCUMENTED Rails position
    # (html_options) must convert to aria-only too — passed through to super it
    # would emit native required, defeating the class-header contract.
    it "converts required in html_options (the documented Rails signature) to aria-only" do
      result = parse(builder.select(:first_name, %w[a b], {}, { required: true }))
      expect(result).to have_css("select[aria-required='true']")
      expect(result).not_to have_css("select[required]")
    end

    it "lets options win over html_options when both carry required" do
      result = parse(builder.select(:first_name, %w[a b], { required: false }, { required: true }))
      expect(result).not_to have_css("select[aria-required]")
      expect(result).not_to have_css("select[required]")
    end
  end

  describe "#checkbox (canonical) and #check_box (alias)" do
    it "renders one 44px label-wrapped target containing the input and caption" do
      result = parse(builder.checkbox(:first_name, label: "I agree"))
      expect(result).to have_css("label.min-h-11 input[type='checkbox']")
      expect(result).to have_css("label.min-h-11", text: "I agree")
    end

    it "produces identical output via the check_box alias" do
      expect(builder.checkbox(:first_name).to_s).to eq(builder.check_box(:first_name).to_s)
    end

    it "gains an error path the old builder never had" do
      user.errors.add(:first_name, "must be accepted")
      result = parse(builder.checkbox(:first_name))
      expect(result).to have_css("p#user_first_name-error", text: "must be accepted")
      expect(result).to have_css("input[type='checkbox'][aria-invalid='true'][aria-describedby='user_first_name-error']")
    end
  end

  describe "#collection_checkboxes / #collection_radio_buttons" do
    let(:roles) { [ [ "1", "Admin" ], [ "2", "Editor" ] ] }

    it "wires the fieldset's aria-describedby and per-input aria-invalid (closes #715)" do
      user.errors.add(:first_name, "pick at least one")
      result = parse(builder.collection_checkboxes(:first_name, roles, :first, :last, help: "Who can edit"))

      expect(result).to have_css("fieldset[aria-describedby='user_first_name-error user_first_name-hint']")
      expect(result).to have_css("fieldset legend", text: "First name")
      expect(result.all("input[type='checkbox'][aria-invalid='true']").size).to eq(2)
    end

    it "renders every collection row as a 44px label-wrapped target" do
      result = parse(builder.collection_checkboxes(:first_name, roles, :first, :last))
      expect(result.all("fieldset label.min-h-11 input[type='checkbox']").size).to eq(2)
    end

    it "collection_check_boxes alias produces identical output to collection_checkboxes" do
      expect(builder.collection_checkboxes(:first_name, roles, :first, :last).to_s).to(
        eq(builder.collection_check_boxes(:first_name, roles, :first, :last).to_s)
      )
    end

    it "mirrors the same contract for radio buttons" do
      user.errors.add(:first_name, "pick one")
      result = parse(builder.collection_radio_buttons(:first_name, roles, :first, :last))
      expect(result).to have_css("fieldset[aria-describedby='user_first_name-error']")
      expect(result.all("fieldset label.min-h-11 input[type='radio'][aria-invalid='true']").size).to eq(2)
    end

    # v0.13.0 contract fix (gem #145): required left in html_options would emit
    # native required on EVERY input in the group — strip it from both hashes.
    it "strips required from html_options so no group input gets native required" do
      result = parse(builder.collection_checkboxes(:first_name, roles, :first, :last, {}, { required: true }))
      expect(result).not_to have_css("input[required]")
      expect(result).to have_css("fieldset legend .text-danger", text: "*")
    end
  end

  describe "#file_field" do
    it "renders a file input bound to its label" do
      result = parse(builder.file_field(:avatar, label: "Photo"))
      expect(result).to have_css("input[type='file']")
      expect(result).to have_css("label", text: "Photo")
    end

    it "is aria-required only, never native required (behavior change from the old builder)" do
      result = parse(builder.file_field(:avatar, required: true))
      expect(result).to have_css("input[type='file'][aria-required='true']")
      expect(result).not_to have_css("input[type='file'][required]")
    end
  end

  describe "#submit" do
    it "defaults to the btn-primary class" do
      result = parse(builder.submit("Save"))
      expect(result).to have_css("input[type='submit'][value='Save'].btn-primary")
    end

    it "REPLACES the default class with a caller class rather than merging" do
      result = parse(builder.submit("Save", class: "btn-secondary"))
      expect(result).to have_css("input[type='submit'].btn-secondary")
      expect(result).not_to have_css("input[type='submit'].btn-primary")
    end
  end

  describe "#error_summary" do
    it "renders nothing when there are no errors" do
      result = builder.error_summary
      expect(result.to_s).to be_blank
    end

    it "renders a focused, linked error summary when errors exist" do
      user.errors.add(:first_name, "can't be blank")
      user.errors.add(:base, "is a duplicate")
      result = parse(builder.error_summary)

      expect(result).to have_css("div[data-slot='error-summary'][tabindex='-1'][autofocus] div[role='alert']")
      expect(result).to have_css("li a[href='#user_first_name']", text: "First name can't be blank")
      expect(result).to have_css("li", text: "is a duplicate")
      expect(result).not_to have_css("li a[href='#user_base']")
    end

    it "uses the app's error-summary wording" do
      user.errors.add(:first_name, "can't be blank")
      result = parse(builder.error_summary)
      expect(result).to have_css("h2", text: "1 error prevented this form from being saved:")
    end
  end

  describe "value_before_type_cast" do
    it "survives re-render when the numeric cast fails" do
      user.failed_login_attempts = "abc"
      result = parse(builder.number_field(:failed_login_attempts))
      expect(result).to have_css("input[value='abc']")
    end

    # For a record loaded from the database, *_before_type_cast is the stored
    # bytes — for an encrypted attribute, the ciphertext (#902). The raw
    # pre-cast value is only the user's when they assigned it this request.
    it "renders the decrypted value of an encrypted attribute loaded from the database" do
      persisted = User.find(create(:user, email_address: "ada@example.com").id)
      loaded_builder = described_class.new(:user, persisted, vc_test_controller.view_context, {})

      result = parse(loaded_builder.email_field(:email_address))

      expect(result).to have_css("input[value='ada@example.com']")
    end

    it "keeps the user's raw input for an encrypted attribute on re-render" do
      user.email_address = "not an address"
      result = parse(builder.email_field(:email_address))

      expect(result).to have_css("input[value='not an address']")
    end
  end
end
