# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/modelrails"

RSpec.describe RuboCop::Cop::ModelRails::NoI18nDefault, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:config) { RuboCop::Config.new("ModelRails/NoI18nDefault" => { "Enabled" => true }) }

  it "flags a literal default on t()" do
    expect_offense(<<~RUBY, "app/helpers/things_helper.rb")
      t("things.title", default: "Things")
                        ^^^^^^^^^^^^^^^^^ A `default:` on a translation call silences both i18n gates for this key, so a missing key looks healthy forever. Fix: put the text under the key in config/locales/en/ (`bundle exec i18n-tasks add-missing` files it) and drop the default; a dynamic key gets a spec proving every value has one. Pattern: keys, never fallbacks. Read: /docs/developer/i18n (No inline defaults).
    RUBY
  end

  it "flags a computed default on I18n.t and on translate" do
    expect_offense(<<~'RUBY', "app/lib/things/tool.rb")
      I18n.t("things.#{key}.name", default: key.to_s.humanize)
                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^ A `default:` on a translation call silences both i18n gates for this key, so a missing key looks healthy forever. Fix: put the text under the key in config/locales/en/ (`bundle exec i18n-tasks add-missing` files it) and drop the default; a dynamic key gets a spec proving every value has one. Pattern: keys, never fallbacks. Read: /docs/developer/i18n (No inline defaults).
      translate(".title", default: t(".other"))
                          ^^^^^^^^^^^^^^^^^^^^ A `default:` on a translation call silences both i18n gates for this key, so a missing key looks healthy forever. Fix: put the text under the key in config/locales/en/ (`bundle exec i18n-tasks add-missing` files it) and drop the default; a dynamic key gets a spec proving every value has one. Pattern: keys, never fallbacks. Read: /docs/developer/i18n (No inline defaults).
    RUBY
  end

  it "accepts translation calls without a default, and default: on other methods" do
    expect_no_offenses(<<~RUBY, "app/helpers/things_helper.rb")
      t("things.title")
      I18n.t("things.count", count: 3)
      options.fetch(:size, default: :md)
      Data.define(:key, default: nil)
    RUBY
  end

  # The message's fourth part names a page and a section (playbook
  # conventions: every machine verdict says four things).
  it "points at a section that exists" do
    page = File.read(File.expand_path("../../../../app/docs/developer/i18n.md", __dir__))
    expect(page).to include("No inline defaults")
  end
end
