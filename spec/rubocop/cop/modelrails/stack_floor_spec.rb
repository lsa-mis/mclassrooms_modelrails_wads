# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/modelrails"

RSpec.describe RuboCop::Cop::ModelRails::StackFloor, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) { RuboCop::Config.new("ModelRails/StackFloor" => { "Enabled" => true }) }

  it "flags the gems the stack replaces, naming what replaces each" do
    expect_offense(<<~RUBY, "Gemfile")
      gem "devise"
      ^^^^^^^^^^^^ `devise` is below the stack floor: the app uses Rails' built-in authentication. Fix: remove the gem and build on what the stack already has. Pattern: Rails 8.1+ floor. Read: /docs/developer/getting-started (The stack).
      gem "jsbundling-rails", "~> 1.3"
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `jsbundling-rails` is below the stack floor: the app uses import maps and tailwindcss-rails, no bundler. Fix: remove the gem and build on what the stack already has. Pattern: Rails 8.1+ floor. Read: /docs/developer/getting-started (The stack).
      gem "react-rails"
      ^^^^^^^^^^^^^^^^^ `react-rails` is below the stack floor: the app uses Hotwire. Fix: remove the gem and build on what the stack already has. Pattern: Rails 8.1+ floor. Read: /docs/developer/getting-started (The stack).
      gem "sprockets-rails"
      ^^^^^^^^^^^^^^^^^^^^^ `sprockets-rails` is below the stack floor: the app uses Propshaft. Fix: remove the gem and build on what the stack already has. Pattern: Rails 8.1+ floor. Read: /docs/developer/getting-started (The stack).
      gem "sidekiq"
      ^^^^^^^^^^^^^ `sidekiq` is below the stack floor: the app uses Solid Queue. Fix: remove the gem and build on what the stack already has. Pattern: Rails 8.1+ floor. Read: /docs/developer/getting-started (The stack).
    RUBY
  end

  it "flags a rails requirement below 8.1" do
    expect_offense(<<~RUBY, "Gemfile")
      gem "rails", "~> 7.2"
      ^^^^^^^^^^^^^^^^^^^^^ `rails` is pinned below the stack floor (`"~> 7.2"`): the app is Rails 8.1 or newer. Fix: raise the requirement and run the upgrade. Pattern: Rails 8.1+ floor. Read: /docs/developer/getting-started (The stack).
    RUBY
  end

  it "accepts the stack itself" do
    expect_no_offenses(<<~RUBY, "Gemfile")
      gem "rails", "~> 8.1.3", ">= 8.1.3.1"
      gem "propshaft"
      gem "importmap-rails"
      gem "turbo-rails"
      gem "solid_queue"
      gem "pundit"
    RUBY
  end

  # The message's fourth part names a page and a section (playbook
  # conventions: every machine verdict says four things).
  it "points at a section that exists" do
    page = File.read(File.expand_path("../../../../app/docs/developer/getting-started.md", __dir__))
    expect(page).to include("## The stack")
  end
end
