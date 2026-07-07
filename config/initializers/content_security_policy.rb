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
    policy.script_src  :self, "https://cdn.jsdelivr.net"
    policy.style_src   :self, :unsafe_inline
    policy.connect_src :self
    policy.frame_src   :none
    policy.base_uri    :self
    # OAuth providers need form-action allowance because CSP evaluates the
    # entire redirect chain. POST to /auth/:provider returns a 302 to the
    # provider's consent page, and browsers block that step unless the
    # provider host is in form-action.
    #
    # Okta's host is a wildcard rather than a fixed domain (unlike Google/
    # GitHub above) because it's org-specific — each Okta customer gets their
    # own "https://<org>.okta.com" subdomain, set at deploy time via
    # OKTA_ISSUER (see config/initializers/omniauth.rb), not baked into this
    # template. Forks using an Okta custom domain, or an *.oktapreview.com
    # sandbox org, need to add that host here too.
    policy.form_action :self,
      "https://accounts.google.com",
      "https://github.com",
      "https://*.okta.com"
  end

  # Generate session nonces for permitted importmap and inline scripts.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Enforce CSP in development and production. Report-only in test because
  # Playwright system specs don't forward nonces to injected scripts.
  config.content_security_policy_report_only = Rails.env.test?
end
