require "rails_helper"

RSpec.describe "Pages", type: :request do
  describe "GET /" do
    it "returns the home page" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.home.title"))
    end
  end

  describe "GET /about" do
    it "returns the about page" do
      get about_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.about.title"))
    end
  end

  describe "GET /privacy" do
    it "returns the privacy page" do
      get privacy_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.privacy.title"))
    end
  end

  describe "GET /contact" do
    it "returns the contact page" do
      get contact_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.contact.title"))
    end
  end
end
