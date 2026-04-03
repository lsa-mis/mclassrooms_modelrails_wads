require "rails_helper"

RSpec.describe TailwindFormBuilder do
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

  # Wrap raw HTML strings so Capybara matchers can query them
  def parse(html)
    Capybara.string(html.to_s)
  end

  describe "#text_field" do
    it "renders an input with base classes" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("input[type='text'].rounded-md")
      expect(result).to have_css("input.min-h-\\[44px\\]")
    end

    it "wraps in a div with space-y-2" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("div.space-y-2")
    end

    it "generates a label from the method name" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("label[for='user_first_name']", text: "First name")
    end

    it "uses custom label text when provided" do
      result = parse(builder.text_field(:first_name, label: "Your Name"))
      expect(result).to have_css("label", text: "Your Name")
    end

    it "renders help text when provided" do
      result = parse(builder.text_field(:first_name, help: "Enter your first name"))
      expect(result).to have_css("p#user_first_name-help", text: "Enter your first name")
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

    it "applies error classes to the input" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("input.ring-danger")
    end

    it "renders an inline error message" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("p#user_first_name-error[role='alert']", text: "can't be blank")
    end

    it "applies error styling to the label" do
      result = parse(builder.text_field(:first_name))
      expect(result).to have_css("label.text-danger")
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
    it "renders a select with options" do
      result = parse(builder.select(:first_name, [ [ "Admin", "admin" ], [ "Member", "member" ] ], label: "Role"))
      expect(result).to have_css("select")
      expect(result).to have_css("option", text: "Admin")
      expect(result).to have_css("label", text: "Role")
    end
  end

  describe "#check_box" do
    it "renders checkbox with label to the right" do
      result = parse(builder.check_box(:first_name, label: "I agree"))
      expect(result).to have_css("div.flex input[type='checkbox']")
      expect(result).to have_css("label", text: "I agree")
    end
  end

  describe "#file_field" do
    it "renders a file input" do
      result = parse(builder.file_field(:avatar, label: "Photo"))
      expect(result).to have_css("input[type='file']")
      expect(result).to have_css("label", text: "Photo")
    end
  end

  describe "#submit" do
    it "renders a submit button with correct classes" do
      result = parse(builder.submit("Save"))
      expect(result).to have_css("input[type='submit'][value='Save']")
      expect(result).to have_css("input.min-h-\\[44px\\]")
      expect(result).to have_css("input.bg-interactive")
    end

    it "merges custom classes" do
      result = parse(builder.submit("Save", class: "w-full"))
      expect(result).to have_css("input.w-full.bg-interactive")
    end
  end

  describe "#error_summary" do
    it "renders nothing when no errors" do
      result = builder.error_summary
      expect(result).to be_nil
    end

    it "renders error banner when errors exist" do
      user.errors.add(:first_name, "can't be blank")
      user.errors.add(:email_address, "is invalid")
      result = parse(builder.error_summary)
      expect(result).to have_css("div[role='alert']")
      expect(result).to have_css("li", count: 2)
    end

    it "includes error count in heading" do
      user.errors.add(:first_name, "can't be blank")
      result = parse(builder.error_summary)
      expect(result).to have_css("h2", text: /1 error/)
    end
  end
end
