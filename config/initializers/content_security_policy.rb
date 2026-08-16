# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :blob, "https://www.gravatar.com"
    policy.object_src  :none
    # cdn.jsdelivr.net is DEVELOPMENT ONLY, mirroring the dev-only chart.js pin
    # in config/importmap.rb (Lookbook) — the two lines must move together. Test
    # enforces CSP with no dev allowance, so a production CDN pin fails the suite.
    policy.script_src(*[ :self, ("https://cdn.jsdelivr.net" if Rails.env.development?) ].compact)
    # unsafe-inline for styles is a DECIDED trade-off (#444): Tailwind 4 and
    # Turbo both write inline styles. See /docs/developer/security (Content
    # Security Policy).
    policy.style_src   :self, :unsafe_inline
    policy.connect_src :self
    policy.frame_src   :none
    policy.base_uri    :self
    # Derived from the provider registry (#312): CSP evaluates the whole OAuth
    # redirect chain, and a missing consent host fails as a SILENT browser-side
    # block. See /docs/developer/security (Content Security Policy).
    policy.form_action :self,
      *Rails.application.config.x.oauth_providers.values.map { |provider| provider.fetch(:form_action_host) }
  end

  # PER-SESSION nonce, not per-request (#443), so Turbo-cached pages still
  # validate on restore; the random fallback covers a visitor's first request,
  # which has no session id yet. See /docs/developer/security (Content
  # Security Policy).
  config.content_security_policy_nonce_generator = lambda do |request|
    request.session.id&.to_s.presence || SecureRandom.base64(16)
  end
  config.content_security_policy_nonce_directives = %w[script-src]

  # Enforcement mode is NOT set here. Rails defaults to enforced (false)
  # everywhere; config/environments/test.rb explicitly enforces it in test
  # too (PR #120) so CSP bugs fail the suite instead of shipping silently.
  # Do not reintroduce a Rails.env.test? override here — an earlier version
  # of this line did exactly that, loaded after test.rb in Rails' boot order,
  # and silently undid PR #120's fix for the lifetime of this bug.
end
