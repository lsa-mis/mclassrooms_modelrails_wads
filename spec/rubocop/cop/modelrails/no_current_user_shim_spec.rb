# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/modelrails"

RSpec.describe RuboCop::Cop::ModelRails::NoCurrentUserShim, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) { RuboCop::Config.new("ModelRails/NoCurrentUserShim" => { "Enabled" => true }) }

  it "flags a current_user definition" do
    expect_offense(<<~RUBY, "app/controllers/things_controller.rb")
      class ThingsController < ApplicationController
        def current_user
        ^^^^^^^^^^^^^^^^ `current_user` is defined once, on ApplicationController, as the bridge Pundit and the mounted engines call; everything else reads `Current.user` (`Current.user!` where nil is a bug). Fix: delete this definition and read Current.user. Pattern: one signed-in-user reader. Read: /docs/developer/architecture (Authorization).
          Current.user
        end
      end
    RUBY
  end

  it "flags an alias or a delegate that mints the name" do
    expect_offense(<<~RUBY, "app/helpers/things_helper.rb")
      alias_method :current_user, :signed_in_user
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `current_user` is defined once, on ApplicationController, as the bridge Pundit and the mounted engines call; everything else reads `Current.user` (`Current.user!` where nil is a bug). Fix: delete this definition and read Current.user. Pattern: one signed-in-user reader. Read: /docs/developer/architecture (Authorization).
      delegate :current_user, to: :context
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `current_user` is defined once, on ApplicationController, as the bridge Pundit and the mounted engines call; everything else reads `Current.user` (`Current.user!` where nil is a bug). Fix: delete this definition and read Current.user. Pattern: one signed-in-user reader. Read: /docs/developer/architecture (Authorization).
    RUBY
  end

  it "accepts reading Current.user, and other names that merely start the same way" do
    expect_no_offenses(<<~RUBY, "app/controllers/things_controller.rb")
      class ThingsController < ApplicationController
        def show
          @thing = Current.user.things.find(params[:id])
        end

        def current_user_theme
          Current.user&.preferences&.theme
        end
      end
    RUBY
  end

  # The message's fourth part names a page and a section (playbook
  # conventions: every machine verdict says four things).
  it "points at a section that exists" do
    page = File.read(File.expand_path("../../../../app/docs/developer/architecture.md", __dir__))
    expect(page).to include("## Authorization")
  end
end
