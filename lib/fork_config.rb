# frozen_string_literal: true

require "yaml"

# The decisions bin/fork recorded in .fork.yml. Stdlib only: bin/ scripts load it before bundle install.
class ForkConfig
  FILE = ".fork.yml"
  PRESETS = %w[personal shared none].freeze

  TENANCY_VARIABLES = %w[WORKSPACE_ON_SIGNUP TENANCY_SHARED_WORKSPACE_SLUG].freeze

  def self.tenancy_env(root, env:, test:)
    recorded = test ? {} : read(root).tenancy_defaults
    recorded.merge(env.to_h.slice(*TENANCY_VARIABLES))
  end

  def self.read(root)
    path = File.join(root, FILE)
    data = YAML.safe_load_file(path) if File.exist?(path)
    new(data.is_a?(Hash) ? data : {})
  end

  def initialize(data)
    @data = data
  end

  def recorded? = @data.any?
  def to_h = @data.dup
  def preset = @data["preset"]
  def name = @data["name"]
  def product_name = @data["product_name"]
  def template_url = @data["template_url"]

  def tenancy_defaults
    return {} unless preset

    defaults = { "WORKSPACE_ON_SIGNUP" => preset }
    # config/initializers/tenancy.rb refuses to boot the shared preset without a slug.
    defaults["TENANCY_SHARED_WORKSPACE_SLUG"] = name if preset == "shared"
    defaults
  end
end
