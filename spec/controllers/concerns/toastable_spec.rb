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

    def update
      render turbo_stream: warning_toast("Watch out")
    end
  end

  render_views

  before do
    routes.draw do
      get "index" => "anonymous#index"
      post "create" => "anonymous#create"
      patch "update" => "anonymous#update"
    end
  end

  describe "#success_toast" do
    it "appends to toast-pills with the pill partial" do
      get :index, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="toast-pills"')
      expect(response.body).to include("It worked")
    end
  end

  describe "#error_toast" do
    it "appends to toast-cards with the card partial" do
      post :create, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="toast-cards"')
      expect(response.body).to include("Something failed")
    end
  end

  describe "#warning_toast" do
    it "appends to toast-cards with the card partial" do
      patch :update, as: :turbo_stream
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="toast-cards"')
      expect(response.body).to include("Watch out")
    end
  end
end
