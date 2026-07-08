require "rails_helper"
require "nokogiri"

# The wireframes carry meaning, so each flow <svg> must be well-formed, named
# for assistive tech, and free of anything the markdowndocs sanitizer would
# strip. Visual correctness is checked in the browser; this guards the contract.
#
# Covers every app/docs/user/application-flows*.md page (the low-fi map and the
# high-fidelity alternate) so both are held to the same bar.
RSpec.describe "Application Flows wireframe pages" do
  pages = Dir[Rails.root.join("app/docs/**/application-flows*.md")].sort

  it "finds the wireframe pages" do
    expect(pages).not_to be_empty
  end

  pages.each do |path|
    slug = File.basename(path, ".md")

    context slug do
      let(:source) { File.read(path) }
      # Each top-level <svg>…</svg> block (flows are not nested).
      let(:svg_blocks) { source.scan(/<svg\b.*?<\/svg>/m) }

      it "has at least the three flow diagrams" do
        expect(svg_blocks.size).to be >= 3
      end

      it "every flow svg is well-formed XML" do
        svg_blocks.each do |svg|
          doc = Nokogiri::XML(svg) { |c| c.strict }
          expect(doc.errors).to be_empty, "malformed SVG in #{slug}: #{doc.errors.first}"
        end
      end

      it "every flow svg is role=img with a non-empty aria-label" do
        svg_blocks.each do |svg|
          root = Nokogiri::XML(svg).root
          expect(root["role"]).to eq("img")
          expect(root["aria-label"].to_s.strip).not_to be_empty
        end
      end

      it "contains no scripts, event handlers, or external refs (sanitizer-safe)" do
        svg_blocks.each do |svg|
          expect(svg).not_to match(/<script/i)
          expect(svg).not_to match(/\son\w+=/i)            # onclick, onload, …
          expect(svg).not_to match(/href\s*=\s*["'](?!#)/i) # only internal #frag refs allowed
        end
      end

      # Source validity is necessary but NOT sufficient: a blank line inside an
      # inline <svg> ends its CommonMark HTML block, and a following chunk whose
      # first line isn't a lone tag becomes a <p> — which closes the <svg> in
      # HTML5 foreign content and orphans every later element (invisible). Only
      # the RENDERED DOM proves the screens actually nest inside their <svg>.
      describe "as rendered through markdowndocs (not just the source)" do
        let(:rendered) do
          body = source.sub(/\A---\n.*?\n---\n/m, "") # drop YAML front matter
          Markdowndocs::MarkdownRenderer.render(body)
        end
        let(:doc) { Nokogiri::HTML5.fragment(rendered) }

        it "nests each flow's drawing elements inside its <svg> (no foreign-content breakout)" do
          svgs = doc.css("svg")
          expect(svgs.size).to be >= 3
          svgs.each do |svg|
            expect(svg.css("rect, circle, text, line").size).to be > 1,
              "svg #{svg['viewBox'].inspect} in #{slug} rendered with no nested screens — CommonMark/HTML5 breakout"
          end
        end

        it "leaves no drawing element orphaned outside an <svg>" do
          orphans = doc.css("rect, circle, line").reject { |n| n.ancestors("svg").any? }
          expect(orphans.size).to eq(0),
            "#{orphans.size} drawing elements rendered outside any <svg> in #{slug} (breakout bug)"
        end

        # Each flow's "Why" is a collapsible <details> (markdowndocs 0.9 allowlists
        # <details>/<summary> under config.allow_svg). The blank line after
        # <summary> is what lets the markdown bullets render INSIDE the disclosure
        # rather than escaping it — assert both survive the pipeline.
        it "renders each Why section as a <details> with its bullets nested inside" do
          details = doc.css("details")
          expect(details.size).to be >= 3
          details.each do |d|
            expect(d.at_css("summary")).to be_present, "a <details> rendered without its <summary> in #{slug}"
            expect(d.css("li").size).to be > 0,
              "a <details>'s bullets escaped the disclosure in #{slug} (missing blank line after <summary>?)"
          end
        end
      end
    end
  end
end
