require "rails_helper"
require "nokogiri"

# The QA flows page opens with a "Developer tools" quick-reference so reviewers
# can reach the dev-only tools (Lookbook, the caught-email inbox) without
# hunting for URLs. See app/docs/developer/qa-flows.md.
RSpec.describe "QA flows developer-tools reference", type: :request do
  it "surfaces the dev-tools quick-reference with links to Lookbook and the dev inbox" do
    get "/docs/developer/qa-flows"
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    hrefs = doc.css("a").map { |a| a["href"] }

    expect(hrefs).to include("/lookbook")       # the addition — not linked from qa-flows before
    expect(hrefs).to include("/letter_opener")  # already referenced; kept in the reference
    expect(doc.text).to match(/Developer tools/i)  # the labelled quick-reference
  end
end
