require "rails_helper"

RSpec.describe TailwindFormBuilder, "WCAG AAA accessibility", type: :component do
  include Capybara::RSpecMatchers

  let(:user) { User.new }
  let(:builder) { described_class.new(:user, user, vc_test_controller.view_context, {}) }

  def parse(html)
    Capybara.string(html.to_s)
  end

  # ---------------------------------------------------------------------------
  # aria-required — never native `required`
  # ---------------------------------------------------------------------------
  describe "aria-required only, never native required" do
    it "sets aria-required=true on text fields when required is passed" do
      result = parse(builder.text_field(:first_name, required: true))
      expect(result).to have_css("input[aria-required='true']")
      expect(result).not_to have_css("input[required]")
    end

    it "does not set aria-required when required is not passed" do
      result = parse(builder.text_field(:first_name))
      expect(result).not_to have_css("input[aria-required]")
    end

    it "sets aria-required on email fields when required" do
      result = parse(builder.email_field(:email_address, required: true))
      expect(result).to have_css("input[aria-required='true']")
      expect(result).not_to have_css("input[required]")
    end

    it "never emits native required on text areas" do
      result = parse(builder.text_area(:first_name, required: true))
      expect(result).to have_css("textarea[aria-required='true']")
      expect(result).not_to have_css("textarea[required]")
    end

    it "never emits native required on file fields (closes the gap the old builder left)" do
      result = parse(builder.file_field(:avatar, required: true))
      expect(result).to have_css("input[type='file'][aria-required='true']")
      expect(result).not_to have_css("input[type='file'][required]")
    end

    it "never emits native required on select" do
      result = parse(builder.select(:first_name, %w[a b], required: true))
      expect(result).to have_css("select[aria-required='true']")
      expect(result).not_to have_css("select[required]")
    end

    it "never emits native required on a single checkbox" do
      result = parse(builder.checkbox(:first_name, required: true))
      expect(result).to have_css("input[type='checkbox'][aria-required='true']")
      expect(result).not_to have_css("input[type='checkbox'][required]")
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
  # aria-describedby — error-first, then hint
  # ---------------------------------------------------------------------------
  describe "aria-describedby" do
    it "links to the hint id when only a hint is present" do
      result = parse(builder.text_field(:first_name, help: "Enter your first name"))
      expect(result).to have_css("input[aria-describedby='user_first_name-hint']")
    end

    context "when the field has errors" do
      before { user.errors.add(:first_name, "can't be blank") }

      it "links to the error id when only errors are present" do
        result = parse(builder.text_field(:first_name))
        expect(result).to have_css("input[aria-describedby='user_first_name-error']")
      end

      it "orders error-first, then hint, when both are present" do
        result = parse(builder.text_field(:first_name, help: "Enter your first name"))
        expect(result).to have_css("input[aria-describedby='user_first_name-error user_first_name-hint']")
      end
    end

    it "does not set aria-describedby when neither hint nor errors are present" do
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
    it "shows a decorative, aria-hidden asterisk when required" do
      result = parse(builder.text_field(:first_name, required: true))
      expect(result).to have_css("label span[aria-hidden='true']", text: "*")
    end

    it "does not render an asterisk when not required" do
      result = parse(builder.text_field(:first_name))
      expect(result).not_to have_css("label span", text: "*")
    end
  end

  # ---------------------------------------------------------------------------
  # Error messages — plain markup, not a field-level live region
  # ---------------------------------------------------------------------------
  describe "error message accessibility" do
    before { user.errors.add(:first_name, "can't be blank") }

    # A field-level live region never fires on a server-rendered response — the
    # region has to exist before its content changes to announce anything.
    # ErrorSummary (asserted below) is the actual, focused announcement
    # mechanism; the inline error paragraph is intentionally plain markup now.
    it "does NOT render the field-level error with role=alert" do
      result = parse(builder.text_field(:first_name))
      expect(result).not_to have_css("[role='alert']", text: "can't be blank")
    end

    it "gives the error element a unique id for aria-describedby linkage" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("p#user_first_name-error")
    end

    it "error element id matches the aria-describedby value on the input" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("input[aria-describedby~='user_first_name-error']")
      expect(result).to have_css("p#user_first_name-error")
    end
  end

  # ---------------------------------------------------------------------------
  # Error indication is not color-only (WCAG 1.4.1) — error labels stop tinting
  # ---------------------------------------------------------------------------
  describe "error indication beyond color alone" do
    before { user.errors.add(:first_name, "can't be blank") }

    it "sets aria-invalid so the control's error styling triggers structurally" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("input[aria-invalid='true']")
    end

    it "renders a visible text error message" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("p.text-danger", text: "can't be blank")
    end

    # Labels no longer tint red on error (a deliberate visual change in this
    # adoption) — the invalid control + the visible error paragraph are the
    # error indicators now, not label color.
    it "does not change the label's text color class on error" do
      result = parse(builder.text_field(:first_name))
      expect(result).not_to have_css("label.text-danger")
    end
  end

  # ---------------------------------------------------------------------------
  # Touch targets — 44px minimum (WCAG 2.5.5)
  # ---------------------------------------------------------------------------
  describe "touch target size" do
    it "applies .btn-primary to submit buttons (btn-primary defines the min-h token)" do
      result = parse(builder.submit("Save"))
      expect(result).to have_css("input[type='submit'].btn-primary")
    end

    # Closes #717: base's old checkbox rendered the input and label as two
    # separate siblings, no single element carrying a full 44px target. The
    # new contract wraps input + caption in ONE label.min-h-11 — one row is
    # one target.
    it "wraps a single checkbox's input and caption in one 44px label target (closes #717)" do
      result = parse(builder.checkbox(:first_name, label: "I agree"))
      expect(result).to have_css("label.min-h-11 input[type='checkbox']")
      expect(result).to have_css("label.min-h-11", text: "I agree")
    end

    it "wraps every collection row in one 44px label target (closes #717)" do
      roles = [ [ "1", "Admin" ], [ "2", "Editor" ] ]
      result = parse(builder.collection_checkboxes(:first_name, roles, :first, :last))
      expect(result.all("fieldset label.min-h-11 input[type='checkbox']").size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Single-checkbox error path (closes #716) — base's old builder had none
  # ---------------------------------------------------------------------------
  describe "single checkbox error path" do
    before { user.errors.add(:first_name, "must be accepted") }

    it "renders an error paragraph wired via aria-describedby (closes #716)" do
      result = parse(builder.checkbox(:first_name))
      expect(result).to have_css("p#user_first_name-error", text: "must be accepted")
      expect(result).to have_css("input[type='checkbox'][aria-invalid='true']" \
                                  "[aria-describedby='user_first_name-error']")
    end
  end

  # ---------------------------------------------------------------------------
  # Collection fieldsets — group-level describedby + per-input aria-invalid
  # (closes #715) — base's old builder had neither
  # ---------------------------------------------------------------------------
  describe "collection fieldset accessibility" do
    before { user.errors.add(:first_name, "pick at least one") }

    it "wires the fieldset's own aria-describedby (closes #715)" do
      roles = [ [ "1", "Admin" ], [ "2", "Editor" ] ]
      result = parse(builder.collection_checkboxes(:first_name, roles, :first, :last, help: "Who can edit"))
      expect(result).to have_css("fieldset[aria-describedby='user_first_name-error user_first_name-hint']")
    end

    it "sets aria-invalid on every collection input, not just the group (closes #715)" do
      roles = [ [ "1", "Admin" ], [ "2", "Editor" ] ]
      result = parse(builder.collection_checkboxes(:first_name, roles, :first, :last))
      expect(result.all("input[type='checkbox'][aria-invalid='true']").size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Error summary — the real live-region announcement mechanism
  # ---------------------------------------------------------------------------
  describe "error summary accessibility" do
    it "is a focused, autofocused live region with links to each field" do
      user.errors.add(:first_name, "can't be blank")
      result = parse(builder.error_summary)
      expect(result).to have_css("div[role='alert'][tabindex='-1'][autofocus]")
      expect(result).to have_css("li a[href='#user_first_name']")
    end

    it "does not link a :base error to a field" do
      user.errors.add(:base, "is a duplicate")
      result = parse(builder.error_summary)
      expect(result).not_to have_css("li a[href='#user_base']")
      expect(result).to have_css("li", text: "is a duplicate")
    end
  end
end
