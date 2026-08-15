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
    # cdn.jsdelivr.net is allowed in DEVELOPMENT ONLY, mirroring the dev-only
    # chart.js pin in config/importmap.rb (the Lookbook catalog) — the two
    # lines must move together. Production and test run script-src 'self':
    # a CDN-pinned module in production fails as a silent module-load error
    # (the lazy import() rejects, the feature does nothing) — and because
    # test enforces CSP (PR #120) and carries no dev allowance, a production
    # CDN pin fails the suite before it ships. This env conditional gates
    # DIRECTIVE CONTENTS, not enforcement mode — see the warning at the
    # bottom of this file, which is about the latter.
    policy.script_src(*[ :self, ("https://cdn.jsdelivr.net" if Rails.env.development?) ].compact)
    # style-src carries unsafe-inline as a DECIDED, documented trade-off
    # (#444), not an oversight: Tailwind 4 injects inline style attributes and
    # Turbo writes inline styles during morphs/transitions, so a nonce/hash
    # regime breaks rendering in ways that resurface with every framework
    # update — a permanent breakage tax. The risk accepted is narrow:
    # style-only injection (no script execution path; script-src stays 'self'
    # + nonce). Revisit only if Tailwind/Turbo ship nonce-compatible styling,
    # not before.
    policy.style_src   :self, :unsafe_inline
    policy.connect_src :self
    policy.frame_src   :none
    policy.base_uri    :self
    # OAuth providers need form-action allowance because CSP evaluates the
    # entire redirect chain. POST to /auth/:provider returns a 302 to the
    # provider's consent page, and browsers block that step unless the
    # provider host is in form-action — SILENTLY: no server error, nothing in
    # the logs, "clicking Sign in with SSO does nothing." Derived from the
    # provider registry (#312) so a swapped provider can never be forgotten
    # here; fetch raises at boot on an entry without a host.
    policy.form_action :self,
      *Rails.application.config.x.oauth_providers.values.map { |provider| provider.fetch(:form_action_host) }
  end

  # Generate session nonces for permitted importmap and inline scripts. A
  # visitor's FIRST request has no session yet, so request.session.id is nil
  # there — falling back to a random nonce avoids emitting the invalid
  # `script-src ... 'nonce-'` (blank) that browsers ignore, which blocks
  # every inline script (the importmap bootstrap + `import "application"`),
  # leaving Stimulus never booting for first-time visitors.
  #
  # PER-SESSION, not per-request, is the decided trade-off (#443): the same
  # nonce for a session's lifetime lets Turbo cache/restore pages whose
  # inline bootstrap still validates (a per-request nonce invalidates every
  # cached page's scripts on restore). Cost accepted: a nonce leaked from one
  # response is valid for the rest of that session, a marginal loss since
  # the session cookie it derives from is the larger secret. Revisit only
  # with a concrete injection vector that per-request would have stopped.
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
