# frozen_string_literal: true

require "rails_helper"

# A component preview must render without leaving the machine (#1207).
#
# Six previews had drifted to four third-party hosts — a real map, a real
# video, a real QR, a real avatar — presumably so the gallery looked
# convincing. Every system spec that audits a preview then waits on that fetch,
# which cost three things: the suite could not run offline (it blocked a push
# twice in one evening), every run in every fork made outbound requests nothing
# declared, and the failure named a component rather than the network, so
# whoever hit it bisected their own change first.
#
# `src:` only, deliberately. A preview may legitimately CONTAIN an absolute URL
# as a value it displays — `copy` shows an invitation link, `device_mockup`
# renders a browser chrome's address bar — and those fetch nothing.
RSpec.describe "Code smell: component previews fetch nothing off-host" do
  # `let`, not bare constants: a SCREAMING_CASE constant in a describe block
  # lands on Object and collides across parallel workers (#607).
  let(:preview_root) { Rails.root.join("spec/components/previews") }

  # `src: "https://…"` or `src: "http://…"`. A `data:` URI is the fix, and a
  # root-relative path is same-origin, so neither matches.
  let(:off_host_src) { /\bsrc:\s*["']https?:\/\// }

  it "no preview passes an off-host absolute URL as src:" do
    offenders = Dir.glob(preview_root.join("**/*")).select { |p| File.file?(p) }.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        next unless line.match?(off_host_src)

        "#{Pathname.new(path).relative_path_from(Rails.root)}:#{i + 1}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      These previews fetch from a third-party host, so the spec auditing each
      one waits on the network:

        #{offenders.join("\n  ")}

      Use a `data:` URI (an inline SVG for an image, a tiny document for an
      iframe) or a same-origin path. What the preview demonstrates does not
      need a real remote document to prove.
    MSG
  end

  # A regex that matches nothing asserts nothing. This pins the pattern against
  # the exact string it exists to catch.
  it "matches the shape it is meant to catch" do
    expect(%(  src: "https://i.pravatar.cc/128",)).to match(off_host_src)
    expect(%(<%= ui :avatar, src: 'http://example.com/a.png' %>)).to match(off_host_src)
    expect(%(  src: "data:image/svg+xml,%3Csvg%3E",)).not_to match(off_host_src)
    expect(%(  src: "/this-image-does-not-exist.png",)).not_to match(off_host_src)
    # The exclusion that matters: a displayed value is not a fetch.
    expect(%(ui :copy, value: "https://example.test/invitations/abc")).not_to match(off_host_src)
    expect(%(ui :device_mockup, url: "https://example.com/dashboard")).not_to match(off_host_src)
  end
end
