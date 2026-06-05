require "rails_helper"

RSpec.describe TailwindFormBuilder, "WCAG AAA accessibility" do
  include Capybara::RSpecMatchers

  let(:user) { User.new }
  let(:builder) { described_class.new(:user, user, template, {}) }
  let(:template) { ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil) }

  before do
    template.class.include ActionView::Helpers::FormHelper
    template.class.include ActionView::Helpers::TagHelper
    template.class.include ActionView::Context
    template.class.include IconHelper
  end

  def parse(html)
    Capybara.string(html.to_s)
  end

  # ---------------------------------------------------------------------------
  # aria-required
  # ---------------------------------------------------------------------------
  describe "aria-required" do
    it "sets aria-required=true when required option is passed" do
      result = parse(builder.text_field(:first_name, required: true))
      expect(result).to have_css("input[aria-required='true']")
    end

    it "does not set aria-required when required is not passed" do
      result = parse(builder.text_field(:first_name))
      expect(result).not_to have_css("input[aria-required]")
    end

    it "sets aria-required=true on email fields when required" do
      result = parse(builder.email_field(:email_address, required: true))
      expect(result).to have_css("input[aria-required='true']")
    end

    it "does not set aria-required on email fields when not required" do
      result = parse(builder.email_field(:email_address))
      expect(result).not_to have_css("input[aria-required]")
    end

    # Required state is advertised via aria-required ONLY, never the native HTML
    # `required` attribute. A native `required` lets the browser block empty
    # submits before they reach the server, suppressing the app's server-rendered
    # error summary/inline errors (see spec/system/registration_validation_spec.rb).
    it "does not emit a native HTML required attribute on inputs when required" do
      result = parse(builder.text_field(:first_name, required: true))
      expect(result).to have_css("input[aria-required='true']")
      expect(result).not_to have_css("input[required]")
    end

    it "does not emit a native HTML required attribute on text areas when required" do
      result = parse(builder.text_area(:first_name, required: true))
      expect(result).to have_css("textarea[aria-required='true']")
      expect(result).not_to have_css("textarea[required]")
    end
  end

  # ---------------------------------------------------------------------------
  # aria-invalid
  # ---------------------------------------------------------------------------
  describe "aria-invalid" do
    context "when the field has errors" do
      before { user.errors.add(:first_name, "can't be blank") }

      it "sets aria-invalid=true on the input" do
        result = parse(builder.text_field(:first_name))
        expect(result).to have_css("input[aria-invalid='true']")
      end
    end

    context "when the field has no errors" do
      it "does not set aria-invalid on the input" do
        result = parse(builder.text_field(:first_name))
        expect(result).not_to have_css("input[aria-invalid]")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # aria-describedby
  # ---------------------------------------------------------------------------
  describe "aria-describedby" do
    it "links to help text ID when only help text is present" do
      result = parse(builder.text_field(:first_name, help: "Enter your first name"))
      expect(result).to have_css("input[aria-describedby='user_first_name-help']")
    end

    context "when the field has errors" do
      before { user.errors.add(:first_name, "can't be blank") }

      it "links to error ID when only errors are present" do
        result = parse(builder.text_field(:first_name))
        expect(result).to have_css("input[aria-describedby='user_first_name-error']")
      end

      it "links to both help and error IDs when both are present" do
        result = parse(builder.text_field(:first_name, help: "Enter your first name"))
        expect(result).to have_css("input[aria-describedby='user_first_name-help user_first_name-error']")
      end
    end

    it "does not set aria-describedby when neither help nor errors are present" do
      result = parse(builder.text_field(:first_name))
      expect(result).not_to have_css("input[aria-describedby]")
    end
  end

  # ---------------------------------------------------------------------------
  # Labels — for/id association
  # ---------------------------------------------------------------------------
  describe "label-input association" do
    it "label for attribute matches input id on text fields" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("label[for='user_first_name']")
      expect(result).to have_css("input#user_first_name")
    end

    it "label for attribute matches input id on email fields" do
      result = parse(builder.email_field(:email_address))
      expect(result).to have_css("label[for='user_email_address']")
      expect(result).to have_css("input#user_email_address")
    end

    it "label for attribute matches input id on password fields" do
      result = parse(builder.password_field(:password))
      expect(result).to have_css("label[for='user_password']")
      expect(result).to have_css("input#user_password")
    end
  end

  # ---------------------------------------------------------------------------
  # Required indicators in labels
  # ---------------------------------------------------------------------------
  describe "required indicator in label" do
    it "shows a red asterisk span in the label when required" do
      result = parse(builder.text_field(:first_name, required: true))
      expect(result).to have_css("label span.text-danger", text: "*")
    end

    it "does not render an asterisk span in the label when not required" do
      result = parse(builder.text_field(:first_name))
      expect(result).not_to have_css("label span.text-danger", text: "*")
    end
  end

  # ---------------------------------------------------------------------------
  # Error messages — role=alert and unique ID
  # ---------------------------------------------------------------------------
  describe "error message accessibility" do
    before { user.errors.add(:first_name, "can't be blank") }

    it "renders error message with role=alert" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("[role='alert']", text: "can't be blank")
    end

    it "gives the error element a unique ID for aria-describedby linkage" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("p#user_first_name-error")
    end

    it "error element ID matches the aria-describedby value on the input" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("input[aria-describedby~='user_first_name-error']")
      expect(result).to have_css("p#user_first_name-error")
    end
  end

  # ---------------------------------------------------------------------------
  # Error indication is not color-only (WCAG 1.4.1)
  # ---------------------------------------------------------------------------
  describe "error indication beyond color alone" do
    before { user.errors.add(:first_name, "can't be blank") }

    it "sets aria-invalid so .form-field[aria-invalid] CSS triggers structural error styling" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("input[aria-invalid='true']")
    end

    it "renders a visible text error message" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("p.text-danger", text: "can't be blank")
    end

    it "changes the label text color class to indicate error state" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("label.text-danger")
    end
  end

  # ---------------------------------------------------------------------------
  # Touch targets — 44px minimum (WCAG 2.5.5)
  # ---------------------------------------------------------------------------
  describe "touch target size" do
    it "applies .form-field to text field inputs (form-field defines min-h token)" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("input.form-field")
    end

    it "applies .form-field to email field inputs" do
      result = parse(builder.email_field(:email_address))
      expect(result).to have_css("input.form-field")
    end

    it "applies .form-field to password field inputs" do
      result = parse(builder.password_field(:password))
      expect(result).to have_css("input.form-field")
    end

    it "applies .btn-primary to submit buttons (btn-primary defines min-h token)" do
      result = parse(builder.submit("Save"))
      expect(result).to have_css("input[type='submit'].btn-primary")
    end
  end
end
