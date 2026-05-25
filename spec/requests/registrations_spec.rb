require "rails_helper"

RSpec.describe "Registrations", type: :request do
  describe "GET /signup" do
    context "when signups are open via config" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

      it "renders :new" do
        get new_registration_path
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("registrations.new.title"))
      end
    end

    context "when the visitor is already signed in" do
      it "redirects to root with an already-signed-in notice" do
        sign_in(create(:user))
        get new_registration_path
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq(I18n.t("authentication.already_signed_in"))
      end
    end

    context "when SIGNUP_MODE is :invite_only" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      it "renders :closed when there is no invitation token in session" do
        get new_registration_path
        expect(response).to render_template(:closed)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("registrations.closed.title"))
      end

      it "renders :new when a valid invitation token is in session" do
        invitation = create(:invitation)
        # POST to the invitation acceptance route — sets session[:pending_invitation_token]
        post accept_invitation_path(token: invitation.token)
        expect(response).to have_http_status(:found).or have_http_status(:see_other)

        get new_registration_path
        expect(response).to render_template(:new)
      end
    end
  end

  describe "POST /signup" do
    context "when signups are open via config" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

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

      context "with duplicate email" do
        it "rejects registration" do
          create(:user, email_address: "taken@example.com")
          post registration_path, params: {
            user: {
              email_address: "taken@example.com",
              first_name: "Jane",
              last_name: "Doe",
              password: "SecureP@ssw0rd123!",
              password_confirmation: "SecureP@ssw0rd123!"
            }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "with blank fields" do
        it "rejects blank email" do
          post registration_path, params: {
            user: { email_address: "", first_name: "Jane", last_name: "Doe",
                    password: "SecureP@ssw0rd123!", password_confirmation: "SecureP@ssw0rd123!" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "rejects blank first name" do
          post registration_path, params: {
            user: { email_address: "new@example.com", first_name: "", last_name: "Doe",
                    password: "SecureP@ssw0rd123!", password_confirmation: "SecureP@ssw0rd123!" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "rejects blank last name" do
          post registration_path, params: {
            user: { email_address: "new@example.com", first_name: "Jane", last_name: "",
                    password: "SecureP@ssw0rd123!", password_confirmation: "SecureP@ssw0rd123!" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "with invalid email format" do
        it "rejects email without any structure" do
          post registration_path, params: {
            user: { email_address: "notanemail", first_name: "Jane", last_name: "Doe",
                    password: "SecureP@ssw0rd123!", password_confirmation: "SecureP@ssw0rd123!" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "rejects email without a domain TLD" do
          post registration_path, params: {
            user: { email_address: "user@example", first_name: "Jane", last_name: "Doe",
                    password: "SecureP@ssw0rd123!", password_confirmation: "SecureP@ssw0rd123!" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "with password confirmation mismatch" do
        it "rejects registration" do
          post registration_path, params: {
            user: { email_address: "new@example.com", first_name: "Jane", last_name: "Doe",
                    password: "SecureP@ssw0rd123!", password_confirmation: "DifferentP@ss456!" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "with pwned password" do
        before do
          pwned = instance_double(Pwned::Password, pwned?: true)
          allow(Pwned::Password).to receive(:new).and_return(pwned)
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

    context "when SIGNUP_MODE is :invite_only with no token" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      let(:valid_params) do
        {
          user: {
            email_address: "newuser@example.com",
            first_name: "New",
            last_name: "User",
            password: "supersecret123",
            password_confirmation: "supersecret123"
          }
        }
      end

      it "renders :closed with status 422 and does not create a user" do
        expect {
          post registration_path, params: valid_params
        }.not_to change(User, :count)

        expect(response).to render_template(:closed)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when SIGNUP_MODE is :invite_only with a valid token" do
      let(:invitation) { create(:invitation) }

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        post accept_invitation_path(token: invitation.token)
        expect(response).to have_http_status(:found).or have_http_status(:see_other)
      end

      let(:valid_params) do
        {
          user: {
            email_address: "newuser@example.com",
            first_name: "New",
            last_name: "User",
            password: "supersecret123",
            password_confirmation: "supersecret123"
          }
        }
      end

      it "creates the user and accepts the invitation" do
        expect {
          post registration_path, params: valid_params
        }.to change(User, :count).by(1)

        expect(invitation.reload).to be_accepted
      end
    end

    describe "POST /signup race condition handling" do
      let(:invitation) { create(:invitation, email: "racer@example.com") }
      let(:valid_params) do
        {
          user: {
            email_address: "racer@example.com",
            first_name: "Racer",
            last_name: "Test",
            password: "supersecret123",
            password_confirmation: "supersecret123"
          }
        }
      end

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        # Stash the token via the real invitation acceptance route.
        post accept_invitation_path(token: invitation.token)
        expect(response).to have_http_status(:found).or have_http_status(:see_other)
      end

      it "rolls back user creation when invitation acceptance fails (race detection)" do
        # Simulate the invitation being consumed between gate-pass and accept!
        allow_any_instance_of(Invitation).to receive(:accept!).and_raise(
          ActiveRecord::RecordInvalid.new(invitation)
        )

        expect {
          post registration_path, params: valid_params
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /signup side effects" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

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
