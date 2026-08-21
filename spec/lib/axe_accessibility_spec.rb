require "rails_helper"

RSpec.describe AxeAccessibility, "#format_violation" do
  let(:formatter) { Class.new { include AxeAccessibility }.new }

  context "for a non-color-contrast violation" do
    let(:violation) do
      {
        "id" => "label",
        "help" => "Form elements must have labels",
        "impact" => "serious",
        "nodes" => [ { "html" => "<input>", "failureSummary" => "Fix any of the following:\n  Element does not have an explicit label" } ]
      }
    end

    it "renders id, help, impact, and node html" do
      result = formatter.send(:format_violation, violation)

      expect(result).to include("label: Form elements must have labels")
      expect(result).to include("Impact: serious")
      expect(result).to include("<input>")
    end

    it "renders axe's failureSummary so the prior diagnostic text is preserved" do
      result = formatter.send(:format_violation, violation)

      expect(result).to include("Element does not have an explicit label")
    end

    it "does not render diagnostic sections when violation is not contrast-related" do
      result = formatter.send(:format_violation, violation)

      expect(result).not_to include("Ancestor chain:")
      expect(result).not_to include("Theme:")
    end
  end

  context "for a color-contrast violation with a full _debug payload" do
    let(:debug_payload) do
      {
        "ancestorChain" => [
          { "tag" => "TD", "classes" => "py-3 px-2 text-text-heading",
            "backgroundColor" => "rgba(0, 0, 0, 0)", "opacity" => "1", "transition" => "none" },
          { "tag" => "TR", "classes" => "border-b border-border hover:bg-surface-sunken transition-colors",
            "backgroundColor" => "rgba(0, 0, 0, 0)", "opacity" => "1",
            "transition" => "color 150ms, background-color 150ms" },
          { "tag" => "DIV", "classes" => "mt-6 bg-surface-raised rounded-lg",
            "backgroundColor" => "rgb(30, 41, 59)", "opacity" => "1", "transition" => "none" }
        ],
        "theme" => { "htmlClasses" => "dark", "cookieTheme" => "dark" },
        "animations" => [],
        "timestamp" => 1715459460000
      }
    end

    let(:violation) do
      {
        "id" => "color-contrast-enhanced",
        "help" => "Elements must meet enhanced color contrast",
        "impact" => "serious",
        "nodes" => [ { "html" => "<td>Alice Anderson</td>", "_debug" => debug_payload } ]
      }
    end

    it "renders the ancestor chain with computed backgrounds" do
      result = formatter.send(:format_violation, violation)

      expect(result).to include("Ancestor chain:")
      expect(result).to include("TD")
      expect(result).to include("rgb(30, 41, 59)")
      expect(result).to include("bg-surface-raised")
    end

    it "renders theme state" do
      result = formatter.send(:format_violation, violation)

      expect(result).to include("Theme:")
      expect(result).to include("dark")
    end

    it "reports 'none' when no animations were active at scan time" do
      result = formatter.send(:format_violation, violation)

      expect(result).to include("Animations: none")
    end
  end

  context "for a color-contrast violation with active animations" do
    let(:violation) do
      {
        "id" => "color-contrast",
        "help" => "Elements must meet sufficient color contrast",
        "impact" => "serious",
        "nodes" => [
          {
            "html" => "<tr>...</tr>",
            "_debug" => {
              "ancestorChain" => [],
              "theme" => { "htmlClasses" => "dark", "cookieTheme" => "dark" },
              "animations" => [
                { "type" => "CSSTransition", "currentTime" => 72.5,
                  "effectTargetTag" => "TR", "effectTargetClass" => "transition-colors" }
              ],
              "timestamp" => 1715459460000
            }
          }
        ]
      }
    end

    it "lists each in-flight animation with its effect target" do
      result = formatter.send(:format_violation, violation)

      expect(result).to include("Animations:")
      expect(result).to include("CSSTransition")
      expect(result).to include("TR")
      expect(result).to include("transition-colors")
    end
  end

  context "for a color-contrast violation without a _debug payload" do
    let(:violation) do
      {
        "id" => "color-contrast-enhanced",
        "help" => "Elements must meet enhanced color contrast",
        "impact" => "serious",
        "nodes" => [ { "html" => "<td>Alice Anderson</td>" } ]
      }
    end

    it "renders the basic violation and notes no debug data was captured" do
      result = formatter.send(:format_violation, violation)

      expect(result).to include("color-contrast-enhanced")
      expect(result).to include("<td>Alice Anderson</td>")
      expect(result).to include("(no diagnostic payload captured)")
    end
  end
end
