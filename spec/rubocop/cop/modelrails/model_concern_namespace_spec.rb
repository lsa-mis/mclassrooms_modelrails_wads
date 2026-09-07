# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/modelrails"

RSpec.describe RuboCop::Cop::ModelRails::ModelConcernNamespace, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) { RuboCop::Config.new("ModelRails/ModelConcernNamespace" => { "Enabled" => true }) }

  it "flags a trait written in the compact module form" do
    expect_offense(<<~RUBY, "app/models/invitation/suppression.rb")
      module Invitation::Suppression
             ^^^^^^^^^^^^^^^^^^^^^^^ `Invitation::Suppression` is defined in compact form, so it cannot see the model's constants. Fix: reopen the model and nest the module (`class Invitation < ApplicationRecord; module Suppression`). Pattern: per-model traits. Read: /docs/developer/extending (Per-model traits).
        extend ActiveSupport::Concern
      end
    RUBY
  end

  it "flags a nested class written in the compact form too" do
    expect_offense(<<~RUBY, "app/models/user/email_change.rb")
      class User::EmailChange
            ^^^^^^^^^^^^^^^^^ `User::EmailChange` is defined in compact form, so it cannot see the model's constants. Fix: reopen the model and nest the class (`class User < ApplicationRecord; class EmailChange`). Pattern: per-model traits. Read: /docs/developer/extending (Per-model traits).
      end
    RUBY
  end

  it "accepts the nested form" do
    expect_no_offenses(<<~RUBY, "app/models/invitation/suppression.rb")
      class Invitation < ApplicationRecord
        module Suppression
          extend ActiveSupport::Concern
        end
      end
    RUBY
  end

  it "accepts a namespaced constant that is itself nested inside the model" do
    expect_no_offenses(<<~RUBY, "app/models/user/avatar.rb")
      class User < ApplicationRecord
        module Avatar
          class Variant::Missing < StandardError; end
        end
      end
    RUBY
  end

  # The message's fourth part names a page and a section; this keeps the
  # pointer honest when the page is edited (playbook conventions: every
  # machine verdict says four things).
  it "points at a section that exists" do
    page = File.read(File.expand_path("../../../../app/docs/developer/extending.md", __dir__))
    expect(page).to include("Per-model traits")
  end
end
