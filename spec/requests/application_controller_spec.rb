require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller(ApplicationController) do
    allow_unauthenticated_access only: [ :index ]

    def index
      signups_open?
      signups_open?
      render plain: "ok"
    end
  end

  describe "#signups_open?" do
    context "in :invite_only mode with no token (returns false)" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      it "memoizes the result and calls SignupPolicy at most once per request" do
        call_count = 0
        allow(SignupPolicy).to receive(:allows_signup?).and_wrap_original do |original, **kwargs|
          call_count += 1
          original.call(**kwargs)
        end

        get :index

        expect(call_count).to eq(1)
      end
    end

    context "in :invite_only mode with valid token (returns true)" do
      let(:invitation) { create(:invitation) }

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      end

      it "memoizes the result and calls SignupPolicy at most once per request" do
        # Set session manually since this is a controller spec
        request.session[:pending_invitation_token] = invitation.token

        call_count = 0
        allow(SignupPolicy).to receive(:allows_signup?).and_wrap_original do |original, **kwargs|
          call_count += 1
          original.call(**kwargs)
        end

        get :index

        expect(call_count).to eq(1)
      end
    end
  end
end
