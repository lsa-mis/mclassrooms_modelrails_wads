# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/modelrails"

RSpec.describe RuboCop::Cop::ModelRails::NoAmbientCurrentInModels, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) { RuboCop::Config.new("ModelRails/NoAmbientCurrentInModels" => { "Enabled" => true }) }

  it "flags a Current read in a model, however it is spelled" do
    expect_offense(<<~RUBY, "app/models/membership/ownership.rb")
      class Membership < ApplicationRecord
        module Ownership
          def record_demotion(to_role)
            ActivityLog.create!(actor: Current.user, workspace: ::Current.workspace!)
                                       ^^^^^^^^^^^^ `Current` is request state; a model reads it only inside the audit concern (Trackable) and the opt-in for_current_workspace scope. Fix: take the actor as a parameter (`deactivate!(removed_by:)`) and the tenant from the record's own association. Pattern: actors are parameters. Read: /docs/developer/architecture (Actors are parameters).
                                                                ^^^^^^^^^^^^^^^^^^^^ `Current` is request state; a model reads it only inside the audit concern (Trackable) and the opt-in for_current_workspace scope. Fix: take the actor as a parameter (`deactivate!(removed_by:)`) and the tenant from the record's own association. Pattern: actors are parameters. Read: /docs/developer/architecture (Actors are parameters).
          end
        end
      end
    RUBY
  end

  it "accepts an explicit actor and the record's own tenant" do
    expect_no_offenses(<<~RUBY, "app/models/membership/ownership.rb")
      class Membership < ApplicationRecord
        module Ownership
          def record_demotion(to_role, actor:)
            ActivityLog.create!(actor: actor, workspace: workspace)
          end

          def deactivate!(removed_by:)
            update!(removed_by: removed_by)
          end
        end
      end
    RUBY
  end

  it "does not mistake a model's own Current-named things for the request state" do
    expect_no_offenses(<<~RUBY, "app/models/thing.rb")
      class Thing < ApplicationRecord
        scope :current, -> { where(archived_at: nil) }
        def current_owner
          owner
        end
      end
    RUBY
  end

  # The message's fourth part names a page and a section (playbook
  # conventions: every machine verdict says four things).
  it "points at a section that exists" do
    page = File.read(File.expand_path("../../../../app/docs/developer/architecture.md", __dir__))
    expect(page).to include("Actors are parameters")
  end
end
