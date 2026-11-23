# Stdlib only: CI's changes job runs this before bundle install. See /docs/developer/testing (change lanes).
module ChangeLanes
  Plan = Data.define(:lanes, :full)

  LOCALE_SPECS = %w[
    spec/i18n_spec.rb
    spec/locales/**/*_spec.rb
    spec/code_smells/{dynamic_i18n_keys_have_values,locale_interpolation_tokens_are_supplied,locale_values_use_vocabulary_tokens,project_tools_have_locale_keys}_spec.rb
    spec/config/{i18n_locale_universe,locales_placeholder_normalization,vocabulary_fork,vocabulary_interpolation}_spec.rb
    spec/code_smells/{flash_messages_are_asserted,reading_type,template_invariants}_spec.rb
    spec/bin/fork_spec.rb
    spec/rubocop/cop/modelrails/no_i18n_default_spec.rb
  ].freeze

  LANES = {
    locale: {
      include: %w[config/locales/**/*.yml],
      exclude: [],
      specs: LOCALE_SPECS
    },
    docs: {
      include: %w[app/docs/**/*.md *.md changelog.d/*.md],
      exclude: [],
      specs: %w[
        spec/docs/**/*_spec.rb
        spec/requests/docs_*_spec.rb
        spec/system/docs_*_spec.rb
        spec/code_smells/{btn_text_is_action_row_only,kamal_secrets_hold_no_literals,no_new_bearer_tokens_in_route_paths,no_unscoped_tenant_loads,required_production_config_outputs_are_current,template_invariants}_spec.rb
        spec/initializers/cookie_classification_spec.rb
        spec/lib/comment_block_check_spec.rb
        spec/models/user_password_change_notification_spec.rb
        spec/policies/cross_workspace_authorization_spec.rb
        spec/rubocop/**/*_spec.rb
      ]
    },
    workflows: {
      include: %w[.github/**/* lefthook.yml],
      exclude: %w[.github/workflows/ci.yml .github/actions/**/*],
      specs: %w[
        spec/ci/**/*_spec.rb
        spec/code_smells/template_invariants_spec.rb
        spec/docs/pull_request_template_spec.rb
        spec/docs/release_template_spec.rb
        spec/bin/{fork,parallel_rspec}_spec.rb
        spec/code_smells/axe_teardown_audit_is_always_on_spec.rb
        spec/migrations/fresh_database_migration_spec.rb
      ]
    }
  }.freeze

  CODE_SMELLS = "spec/code_smells/**/*_spec.rb".freeze
  MATCH = File::FNM_PATHNAME | File::FNM_EXTGLOB

  def self.classify(paths)
    lanes = paths.map { |path| lane_for(path) }
    return Plan.new(lanes: [], full: true) if lanes.empty? || lanes.include?(nil)

    Plan.new(lanes: lanes.uniq.sort, full: false)
  end

  def self.specs_for(plan, root:)
    return [] if plan.full

    expand(plan.lanes.flat_map { |lane| LANES.fetch(lane)[:specs] }, root:)
  end

  def self.related_specs(paths, root:)
    expand(paths.flat_map { |path| conventional_specs(path) } + [ CODE_SMELLS ], root:)
  end

  def self.lane_for(path)
    LANES.find do |_lane, rules|
      rules[:include].any? { |glob| File.fnmatch?(glob, path, MATCH) } &&
        rules[:exclude].none? { |glob| File.fnmatch?(glob, path, MATCH) }
    end&.first
  end

  def self.conventional_specs(path)
    case path
    when %r{\Aspec/.+_spec\.rb\z} then [ path ]
    when %r{\Aapp/controllers/(.+)_controller\.rb\z} then [ "spec/requests/#{$1}_spec.rb", "spec/requests/#{$1}/**/*_spec.rb" ]
    when %r{\Aapp/components/(.+)\.html\.erb\z} then [ "spec/components/#{$1}_spec.rb" ]
    when %r{\Aapp/([^/]+)/(.+)\.rb\z} then [ "spec/#{$1}/#{$2}_spec.rb" ]
    when %r{\Alib/(.+)\.rb\z} then [ "spec/lib/#{$1}_spec.rb" ]
    when %r{\Abin/([^/]+)\z} then [ "spec/bin/#{$1.tr("-", "_")}_spec.rb" ]
    else []
    end
  end

  def self.expand(globs, root:)
    globs.flat_map { |glob| Dir.glob(glob, base: root) }.uniq.sort
  end

  private_class_method :lane_for, :conventional_specs, :expand
end
