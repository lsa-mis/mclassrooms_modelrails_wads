require "rails_helper"

# CLAUDE.md states "All controllers must enforce Pundit authorization." This
# spec is the enforcement: every state-changing (POST/PATCH/PUT/DELETE) route
# must resolve to an action that calls Pundit's `authorize` — or be on an
# explicit, reviewed allow-list of actions that are public or act only on the
# current user's own resources. A fork contributor who adds a mutating action
# to a tenant resource and forgets `authorize` gets a red test, not a silent
# IDOR in production.
#
# Detection is route-driven (accurate HTTP verbs) and per-ACTION, and keyed on a
# real `authorize`/`authorize!` call — `authorize_role_grant!` and other
# `authorize_*` helpers are NOT matched, so the check can't be fooled into a
# false pass. The detector is exercised against fixtures below so the lint can
# provably fail.
module AuthorizationAudit
  module_function

  MUTATING_VERBS = %w[POST PATCH PUT DELETE].freeze

  # The body of `def <action> ... end`, matched by indentation.
  def action_body(source, action)
    lines = source.lines
    start = lines.index { |l| l =~ /^(\s*)def #{Regexp.escape(action)}\b/ }
    return nil unless start

    indent = lines[start][/^\s*/].length
    body = [ lines[start] ]
    (start + 1...lines.size).each do |i|
      body << lines[i]
      break if lines[i] =~ /^\s{#{indent}}end\b/
    end
    body.join
  end

  # A real Pundit authorization call — NOT `authorize_role_grant!` etc. (the
  # underscore after "authorize" excludes helper methods).
  def authorized?(body)
    return false unless body
    # Strip trailing line comments (but keep #{interpolation}) so a comment
    # mentioning "authorize" can't produce a false pass.
    code = body.gsub(/#(?!\{).*$/, "")
    !!(code =~ /\bauthorize!?[ (]/) || code.include?("skip_authorization") || code.include?("verify_authorized")
  end

  def action_authorized?(source, action)
    authorized?(action_body(source, action))
  end

  # Every mutating route as "controller#action".
  def mutating_actions
    Rails.application.routes.routes.filter_map do |route|
      next unless MUTATING_VERBS.include?(route.verb)
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next unless controller && action
      next if controller.start_with?("rails/", "active_storage/", "turbo/", "action_")
      next unless File.exist?(controller_path(controller))
      "#{controller}##{action}"
    end.uniq
  end

  def controller_path(controller)
    Rails.root.join("app/controllers/#{controller}_controller.rb")
  end
end

RSpec.describe "Mutating controller actions authorize or are allow-listed" do
  # Actions that legitimately do NOT call `authorize`. Each is either a public
  # auth-entry flow (no signed-in user to authorize) or scoped entirely to
  # Current.user's own resources (no cross-user/tenant surface). Adding to this
  # list is a deliberate, reviewed decision.
  allow_list = %w[
    direct_uploads#create
    email_verification_resends#create
    invitation_accepts#create
    invitation_declines#create
    magic_link_callbacks#create
    magic_link_callbacks#sign_in
    magic_links#create
    password_resets#create
    sessions#create
    sessions#destroy
    sessions#lookup
    sessions#update
    workspaces/joins#create
    passkeys/authentications#options
    passkeys/authentications#verify
    passkeys/reauthentications#options
    passkeys/reauthentications#verify
    passkeys/registrations#options
    passkeys/registrations#verify
    onboardings#update
    passkey_prompts#update
    pending_joins#create
    pending_joins#destroy
    settings/connected_accounts#destroy
    settings/connected_accounts#resend_verification
    settings/email_confirmations#destroy
    settings/notifications#destroy
    settings/notifications#update
    settings/other_sessions#destroy
    settings/passkeys#destroy
    settings/passwords#create
    settings/passwords#destroy
    settings/passwords#update
    settings/reauthentication_codes#create
    settings/reauthentications#create
    settings/sessions#destroy
  ].to_set

  it "every mutating action calls authorize or is explicitly allow-listed" do
    Rails.application.eager_load!

    unauthorized = AuthorizationAudit.mutating_actions.reject do |key|
      controller, action = key.split("#")
      source = File.read(AuthorizationAudit.controller_path(controller))
      AuthorizationAudit.action_authorized?(source, action) || allow_list.include?(key)
    end

    expect(unauthorized).to be_empty, <<~MSG
      Mutating action(s) that neither call `authorize` nor are allow-listed:

      #{unauthorized.sort.join("\n")}

      A state-changing action on a tenant/other-user resource must call Pundit's
      `authorize`. If the action is genuinely public or acts only on the current
      user's own resources, add it to allow_list in this spec with that rationale.
    MSG
  end

  # The lint must be able to fail — prove the detector against fixtures.
  describe "the detector itself" do
    let(:authorized_source) do
      <<~RUBY
        class ThingsController < ApplicationController
          def destroy
            @thing = @workspace.things.find(params[:id])
            authorize @thing
            @thing.destroy
          end
        end
      RUBY
    end

    let(:unauthorized_source) do
      <<~RUBY
        class ThingsController < ApplicationController
          def destroy
            Thing.find(params[:id]).destroy
          end
        end
      RUBY
    end

    let(:helper_false_positive_source) do
      <<~RUBY
        class ThingsController < ApplicationController
          def create
            authorize_role_grant!(@thing, role) # NOT a Pundit authorize call
            @thing.save
          end
        end
      RUBY
    end

    it "passes an action that calls authorize" do
      expect(AuthorizationAudit.action_authorized?(authorized_source, "destroy")).to be(true)
    end

    it "flags an action that never authorizes" do
      expect(AuthorizationAudit.action_authorized?(unauthorized_source, "destroy")).to be(false)
    end

    it "is not fooled by an authorize_* helper method" do
      expect(AuthorizationAudit.action_authorized?(helper_false_positive_source, "create")).to be(false)
    end
  end
end
