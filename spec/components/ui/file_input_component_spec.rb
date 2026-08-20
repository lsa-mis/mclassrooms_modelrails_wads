# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::FileInputComponent, type: :component do
  it "renders the app's file-field styling + a11y params" do
    render_inline(described_class.new(
      name: "user[avatar]", accept: "image/*", invalid: true, describedby: "user_avatar-error"
    ))

    inp = page.find("input[type=file]")
    expect(inp[:name]).to eq("user[avatar]")
    expect(inp[:accept]).to eq("image/*")
    expect(inp["aria-invalid"]).to eq("true")
    expect(inp["aria-describedby"]).to eq("user_avatar-error")
    expect(inp[:class]).to eq("form-file")
  end

  describe "default mode (show_selection omitted)" do
    it "renders the bare input with no wrapper" do
      render_inline(described_class.new(name: "demo_file"))

      expect(page).to have_no_css("[data-controller='file-input']")
      expect(page).to have_no_css("div")
    end

    it "renders no selection list, pill template, or live region" do
      render_inline(described_class.new(name: "demo_file"))

      expect(page).to have_no_css("ul", visible: :all)
      expect(page).to have_no_css("template", visible: :all)
      expect(page).to have_no_css("[aria-live]", visible: :all)
    end
  end

  describe "show_selection: true" do
    it "wraps the input in a file-input controller element" do
      render_inline(described_class.new(show_selection: true))

      expect(page).to have_css("div[data-controller='file-input'] input[type='file']")
    end

    it "wires the input target and change action" do
      render_inline(described_class.new(show_selection: true))

      expect(page).to have_css(
        "input[data-file-input-target='input'][data-action~='change->file-input#update']"
      )
    end

    it "carries the default English label values" do
      render_inline(described_class.new(show_selection: true))

      expect(page).to have_css("div[data-file-input-one-value='1 file selected: %{names}']")
      expect(page).to have_css("div[data-file-input-many-value='%{count} files selected: %{names}']")
      expect(page).to have_css("div[data-file-input-none-value='No files selected']")
    end

    it "merges selection_labels overrides over the defaults" do
      render_inline(described_class.new(
        show_selection: true,
        selection_labels: { many: "%{count} Dateien: %{names}", none: "Keine Dateien" }
      ))

      expect(page).to have_css("div[data-file-input-many-value='%{count} Dateien: %{names}']")
      expect(page).to have_css("div[data-file-input-none-value='Keine Dateien']")
      expect(page).to have_css("div[data-file-input-one-value='1 file selected: %{names}']")
    end

    it "renders the list target hidden until it holds pills" do
      render_inline(described_class.new(show_selection: true))

      expect(page).to have_css("ul[data-file-input-target='list'][hidden]", visible: :all)
    end

    # Capybara's HTML5 parse makes <template> content an inert fragment, so the
    # pill is reached through an HTML4 Nokogiri parse of the rendered output.
    it "gives the pill template the badge soft chip treatment" do
      render_inline(described_class.new(show_selection: true))

      pill = Nokogiri::HTML4.fragment(rendered_content)
        .at_css("template[data-file-input-target=pill] > li")

      expect(pill).not_to be_nil
      expect(pill["class"].split).to include("rounded-full", "bg-interactive-subtle", "text-interactive")
    end

    it "renders the sr-only status live region up front" do
      render_inline(described_class.new(show_selection: true))

      expect(page).to have_css("span.sr-only[aria-live='polite'][data-file-input-target='status']")
    end

    it "keeps input attrs, html_attrs, and a caller data: hash on the input" do
      render_inline(described_class.new(
        show_selection: true, accept: "image/*", multiple: true, required: true,
        invalid: true, describedby: "gallery_error", name: "photos[]", id: "photos",
        data: { testid: "gallery-upload" }
      ))

      expect(page).to have_css(
        "div[data-controller='file-input'] " \
        "input[type='file'][accept='image/*'][multiple][required][aria-required='true']" \
        "[aria-invalid='true'][aria-describedby='gallery_error'][name='photos[]'][id='photos']" \
        "[data-testid='gallery-upload'][data-file-input-target='input']"
      )
    end

    it "keeps the app's form-file styling on the input" do
      render_inline(described_class.new(show_selection: true))

      inp = page.find("div[data-controller='file-input'] input[type='file']")
      expect(inp[:class]).to eq("form-file")
    end
  end
end
