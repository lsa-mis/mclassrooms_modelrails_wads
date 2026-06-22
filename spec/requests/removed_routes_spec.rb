# frozen_string_literal: true

require "rails_helper"

# Guards that confirm password-registration routes are gone after the
# passwordless-first refactor. These assertions flip from RED → GREEN
# when the `resource :registration` route is removed from routes.rb.
RSpec.describe "Removed routes guard", type: :request do
  it "no longer exposes the password registration route (new)" do
    expect { new_registration_path }.to raise_error(NameError)
  end

  it "no longer exposes the password registration route (create)" do
    expect { registration_path }.to raise_error(NameError)
  end

  it "no longer exposes the public password-reset routes" do
    expect { new_password_path }.to raise_error(NameError)
  end
end
