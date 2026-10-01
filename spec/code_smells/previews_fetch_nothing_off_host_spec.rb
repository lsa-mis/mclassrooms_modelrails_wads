# frozen_string_literal: true

require "rails_helper"

# A component preview renders without leaving the machine (#1207). `src:` only: a
# preview may display an absolute URL (copy, device_mockup) without fetching it.
RSpec.describe "Code smell: component previews fetch nothing off-host" do
  let(:preview_root) { Rails.root.join("spec/components/previews") }

  # A data: URI or a root-relative path does not match.
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

  # POSITIVE CONTROL: the pattern against the exact string it exists to catch.
  it "matches the shape it is meant to catch" do
    expect(%(  src: "https://i.pravatar.cc/128",)).to match(off_host_src)
    expect(%(<%= ui :avatar, src: 'http://example.com/a.png' %>)).to match(off_host_src)
    expect(%(  src: "data:image/svg+xml,%3Csvg%3E",)).not_to match(off_host_src)
    expect(%(  src: "/this-image-does-not-exist.png",)).not_to match(off_host_src)
    expect(%(ui :copy, value: "https://example.test/invitations/abc")).not_to match(off_host_src)
    expect(%(ui :device_mockup, url: "https://example.com/dashboard")).not_to match(off_host_src)
  end
end
