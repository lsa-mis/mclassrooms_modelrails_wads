require "rails_helper"

RSpec.describe Toastable, type: :controller do
  controller(ApplicationController) do
    include Toastable
    allow_unauthenticated_access

    def index
      render turbo_stream: success_toast("It worked")
    end

    def create
      render turbo_stream: error_toast("Something failed")
    end
  end

  render_views

  before { routes.draw { get "index" => "anonymous#index"; post "create" => "anonymous#create" } }

  describe "#success_toast" do
    it "returns a turbo stream append to notifications" do
      get :index, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="notifications"')
      expect(response.body).to include("It worked")
    end
  end

  describe "#error_toast" do
    it "returns a turbo stream append to notifications with error type" do
      post :create, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="notifications"')
      expect(response.body).to include("Something failed")
    end
  end
end
