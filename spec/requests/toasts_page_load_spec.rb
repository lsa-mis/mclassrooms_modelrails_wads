# frozen_string_literal: true

require "rails_helper"

# #901: a live region announces changes made after it is registered; content
# already inside it when the page loads is never spoken. A page-load flash
# therefore travels in a <template> beside the empty containers and is moved
# into them after load (toast_flash_controller), so it reaches the region as
# a mutation like a streamed toast does.
RSpec.describe "Page-load flash toasts", type: :request do
  let(:user) { create(:user) }

  it "renders the live-region containers empty and carries the flash in a template beside them" do
    token = MagicLinkToken.create_for_email(user.email_address)
    post magic_link_callback_session_path(token)
    follow_redirect!

    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#toast-pills").element_children).to be_empty
    template = doc.at_css("template[data-controller='toast-flash'][data-toast-flash-container-value='toast-pills']")
    expect(template).to be_present
    expect(template.inner_html).to include(I18n.t("magic_link_callbacks.show.signed_in"))
    expect(template.has_attribute?("data-turbo-temporary")).to be(true)
  end
end
