require "rails_helper"

RSpec.describe "Changing the defaults docs page", type: :request do
  def links_on(body) = Capybara.string(body).all("article a[href]", visible: :all).map { |a| a[:href] }

  { "changing-the-defaults" => 12, "quickstart" => 10 }.each do |slug, at_least|
    it "sends every link on #{slug} to a docs page and heading that exist" do
      doc_path = "/docs/developer/#{slug}"
      get doc_path
      expect(response).to have_http_status(:ok)

      targets = links_on(response.body).map { |href| URI.join("http://www.example.com#{doc_path}", href) }
                                       .select { |uri| uri.host == "www.example.com" && uri.path.start_with?("/docs/") }
      expect(targets.size).to be >= at_least

      broken = targets.reject do |uri|
        get uri.path
        response.ok? && (uri.fragment.nil? || Capybara.string(response.body).has_css?("##{uri.fragment}", visible: :all))
      end
      expect(broken.map(&:to_s)).to be_empty
    end
  end

  it "is linked from the quickstart" do
    get "/docs/developer/quickstart"

    expect(links_on(response.body)).to include("changing-the-defaults")
  end
end
