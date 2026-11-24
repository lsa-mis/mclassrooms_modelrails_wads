# frozen_string_literal: true

require "rails_helper"
require "kamal"
require "commonmarker"

RSpec.describe "the quickstart" do
  let(:pages) { Rails.root.join("app/docs/developer") }
  let(:quickstart) { pages.join("quickstart.md").read }
  let(:heading_ids) do
    lambda do |page|
      html = Commonmarker.to_html(pages.join("#{page}.md").read, options: { extension: { header_ids: "", front_matter_delimiter: "---" } })
      html.scan(/id="([^"]+)"/).flatten
    end
  end

  it "links only to headings the pages it links to have" do
    links = quickstart.scan(/\]\(([a-z0-9-]*)#([^)]+)\)/).map { |page, anchor| [ page.presence || "quickstart", anchor ] }.uniq
    broken = links.reject { |page, anchor| heading_ids.(page).include?(anchor) }

    expect(links.size).to be >= 3
    expect(broken).to be_empty, "no such heading: #{broken.map { |page, anchor| "#{page}##{anchor}" }.join(', ')}"
  end

  it "shows a proxy behind another TLS terminator that Kamal accepts" do
    block = quickstart.scan(/```yaml\n(.*?)```/m).flatten.find { |yaml| yaml.include?("http_port") }
    example = YAML.safe_load(block.to_s).to_h
    proxy_docs = YAML.load_file(File.join(Gem.loaded_specs["kamal"].full_gem_path, "lib/kamal/configuration/docs/proxy.yml"))["proxy"]

    expect(example.dig("proxy", "ssl")).to be(false)
    expect {
      Kamal::Configuration::Validator::Proxy.new(example["proxy"], example: proxy_docs, context: "proxy").validate!
    }.not_to raise_error
  end
end
