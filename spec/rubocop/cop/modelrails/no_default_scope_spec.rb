# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/modelrails"

RSpec.describe RuboCop::Cop::ModelRails::NoDefaultScope, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) { RuboCop::Config.new("ModelRails/NoDefaultScope" => { "Enabled" => true }) }

  it "flags a default_scope block" do
    expect_offense(<<~RUBY, "app/models/milestone.rb")
      class Milestone < ApplicationRecord
        default_scope { where(workspace_id: Current.workspace&.id) }
        ^^^^^^^^^^^^^ `default_scope` scopes every query on this model from a distance, including the ones a job, the console, and an association never meant. Fix: remove it; resolve tenant records through the workspace association (`@workspace.milestones`) or the opt-in `for_current_workspace` scope, and put ordering or filtering in a named scope. Pattern: opt-in tenant scoping. Read: /docs/developer/extending (Decide how it is tenant-scoped).
      end
    RUBY
  end

  it "flags a default_scope lambda" do
    expect_offense(<<~RUBY, "app/models/milestone.rb")
      class Milestone < ApplicationRecord
        default_scope -> { order(:position) }
        ^^^^^^^^^^^^^ `default_scope` scopes every query on this model from a distance, including the ones a job, the console, and an association never meant. Fix: remove it; resolve tenant records through the workspace association (`@workspace.milestones`) or the opt-in `for_current_workspace` scope, and put ordering or filtering in a named scope. Pattern: opt-in tenant scoping. Read: /docs/developer/extending (Decide how it is tenant-scoped).
      end
    RUBY
  end

  it "accepts named scopes and the opt-in tenant scope" do
    expect_no_offenses(<<~RUBY, "app/models/milestone.rb")
      class Milestone < ApplicationRecord
        include Tenanted
        scope :positioned, -> { order(:position) }
        scope :for_current_workspace, -> { where(workspace: Current.workspace) }
      end
    RUBY
  end

  it "accepts unscoped, which is how a caller escapes somebody else's default_scope" do
    expect_no_offenses(<<~RUBY, "app/models/milestone.rb")
      class Milestone < ApplicationRecord
        def self.everything
          unscoped
        end
      end
    RUBY
  end

  # The message's fourth part names a page and a section (playbook
  # conventions: every machine verdict says four things).
  it "points at a section that exists" do
    page = File.read(File.expand_path("../../../../app/docs/developer/extending.md", __dir__))
    expect(page).to include("Decide how it is tenant-scoped")
  end
end
