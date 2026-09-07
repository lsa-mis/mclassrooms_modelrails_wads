# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/modelrails"

RSpec.describe RuboCop::Cop::ModelRails::RestfulActions, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) { RuboCop::Config.new("ModelRails/RestfulActions" => { "Enabled" => true }) }

  it "flags a public method that is not one of the seven actions" do
    expect_offense(<<~RUBY, "app/controllers/things_controller.rb")
      class ThingsController < ApplicationController
        def archive
        ^^^^^^^^^^^ `archive` is not one of the seven REST actions, so it is either a resource that has not been named yet or a helper that is not private. Fix: a verb becomes create/destroy (or update) on a nested resource (`resource :archival`); a helper moves below `private`. Pattern: REST with no cited exceptions. Read: /docs/developer/extending (Only the seven actions).
          @thing.archive!
        end
      end
    RUBY
  end

  it "accepts the seven, private helpers, and class-level macros" do
    expect_no_offenses(<<~RUBY, "app/controllers/things_controller.rb")
      class ThingsController < ApplicationController
        before_action :set_thing, only: [:show, :update]

        def index; end
        def show; end
        def new; end
        def create; end
        def edit; end
        def update; end
        def destroy; end

        private

        def set_thing
          @thing = @workspace.things.find(params[:id])
        end

        def thing_params
          params.require(:thing).permit(:name)
        end
      end
    RUBY
  end

  it "accepts a public method again after a protected or private section is reopened as public, only if it is an action" do
    expect_offense(<<~RUBY, "app/controllers/things_controller.rb")
      class ThingsController < ApplicationController
        private

        def helper; end

        public

        def show; end

        def lookup; end
        ^^^^^^^^^^ `lookup` is not one of the seven REST actions, so it is either a resource that has not been named yet or a helper that is not private. Fix: a verb becomes create/destroy (or update) on a nested resource (`resource :archival`); a helper moves below `private`. Pattern: REST with no cited exceptions. Read: /docs/developer/extending (Only the seven actions).
      end
    RUBY
  end

  # The message's fourth part names a page and a section (playbook
  # conventions: every machine verdict says four things).
  it "points at a section that exists" do
    page = File.read(File.expand_path("../../../../app/docs/developer/extending.md", __dir__))
    expect(page).to include("Only the seven actions")
  end
end
