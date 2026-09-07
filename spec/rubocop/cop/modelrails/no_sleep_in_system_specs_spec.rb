# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/modelrails"

RSpec.describe RuboCop::Cop::ModelRails::NoSleepInSystemSpecs, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) { RuboCop::Config.new("ModelRails/NoSleepInSystemSpecs" => { "Enabled" => true }) }

  it "flags a bare sleep before an assertion" do
    expect_offense(<<~RUBY, "spec/system/things_spec.rb")
      it "saves" do
        click_button "Save"
        sleep 1
        ^^^^^^^ `sleep` waits for a clock, not for the thing you mean, so under load it passes green with the state you wanted still on its way. Fix: wait for observable state (`expect(page).to have_css(...)`, or a bounded poll: `Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until <condition> }`); a wait that gives a request time to NOT arrive carries an inline comment naming what it waits out. Pattern: observable-state waits. Read: /docs/developer/testing (Waiting in system specs).
        expect(page).to have_text("Saved")
      end
    RUBY
  end

  it "accepts sleep as the tick of a modifier until" do
    expect_no_offenses(<<~RUBY, "spec/system/things_spec.rb")
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until opacity.call == "1" }
    RUBY
  end

  it "accepts sleep as the tick inside a loop, an until block, or a times block" do
    expect_no_offenses(<<~RUBY, "spec/system/things_spec.rb")
      Timeout.timeout(Capybara.default_max_wait_time) do
        loop do
          break if user.preferences.reload.timezone.present?
          sleep 0.1
        end
      end
      until settled?
        sleep 0.05
      end
      25.times do
        return true if connected?
        sleep interval
      end
    RUBY
  end

  it "accepts a named negative wait, which carries its reason on the line" do
    expect_no_offenses(<<~RUBY, "spec/system/things_spec.rb")
      expect(page).to have_css("[data-connected]")
      sleep 0.3 # post-connect round-trip margin for a wrongful clobber
    RUBY
  end

  # The message's fourth part names a page and a section (playbook
  # conventions: every machine verdict says four things).
  it "points at a section that exists" do
    page = File.read(File.expand_path("../../../../app/docs/developer/testing.md", __dir__))
    expect(page).to include("Waiting in system specs")
  end
end
