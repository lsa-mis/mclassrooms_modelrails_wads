require "rails_helper"

RSpec.describe "Registrations", type: :request do
  describe "GET /signup" do
    it "renders the registration form" do
      get new_registration_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /signup" do
    context "with valid params" do
      let(:valid_params) do
        {
          user: {
            email_address: "new@example.com",
            first_name: "Jane",
            last_name: "Doe",
            password: "SecureP@ssw0rd123!",
            password_confirmation: "SecureP@ssw0rd123!"
          }
        }
      end

      it "creates a user" do
        expect {
          post registration_path, params: valid_params
        }.to change(User, :count).by(1)
      end

      it "signs in the user" do
        post registration_path, params: valid_params
        expect(response).to redirect_to(root_path)
      end
    end

    context "with password too short" do
      it "rejects registration" do
        post registration_path, params: {
          user: {
            email_address: "new@example.com",
            first_name: "Jane",
            last_name: "Doe",
            password: "short",
            password_confirmation: "short"
          }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with pwned password" do
      before do
        allow_any_instance_of(Pwned::Password).to receive(:pwned?).and_return(true)
      end

      it "rejects registration with a breached password" do
        post registration_path, params: {
          user: {
            email_address: "new@example.com",
            first_name: "Jane",
            last_name: "Doe",
            password: "password123456",
            password_confirmation: "password123456"
          }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /signup side effects" do
    let(:valid_params) do
      {
        user: {
          email_address: "sideeffect@example.com",
          first_name: "Test",
          last_name: "User",
          password: "SecureP@ssw0rd123!",
          password_confirmation: "SecureP@ssw0rd123!"
        }
      }
    end

    it "creates an email authentication record" do
      post registration_path, params: valid_params
      user = User.find_by(email_address: "sideeffect@example.com")
      expect(user.authentications.email.count).to eq(1)
    end

    it "enqueues a verification email" do
      expect {
        post registration_path, params: valid_params
      }.to have_enqueued_mail(AuthenticationMailer, :verification_email)
    end
  end
end
