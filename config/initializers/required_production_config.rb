# Refuses to boot production with configuration that comes up green and broken:
# with a placeholder RAILS_HOST the /up healthcheck passes while every mailer
# link (magic links, password resets, invitations) points at a domain this app
# does not control — the primary sign-in path dies with no visible failure.
#
# Scope discipline: deterministic checks only (unset, or a value that can never
# have been healthy). A previously-healthy configuration must never fail a
# restart. Heuristic placeholder sweeps belong in bin/fork and CI, not here.
#
# Opt out: `git rm config/initializers/required_production_config.rb`. The file
# is deliberately self-contained so removing it is one command, not a merge
# conflict. See /docs/developer/deployment (Production preflight).
module RequiredProductionConfig
  # example.com is IANA-reserved (RFC 2606); `.example` is the TLD bin/fork
  # substitutes into placeholders. Neither can ever be a real deployment host.
  PLACEHOLDER_HOST = /\A(.+\.)?example(\.com)?\z/

  def self.check!(env = ENV)
    host = env["RAILS_HOST"].to_s.strip
    return unless host.empty? || PLACEHOLDER_HOST.match?(host)

    raise <<~MSG
      Production preflight failed: RAILS_HOST is #{host.empty? ? "unset" : host.inspect}.

      Every mailer link (magic links, password resets, invitations) is built from
      RAILS_HOST, and DNS-rebinding protection (config.hosts) is derived from it.
      With a placeholder value the app boots, /up reports healthy, and nobody can
      sign in — the failure is invisible from the outside.

      Fix: set RAILS_HOST to this deployment's public hostname (e.g. app.yourdomain.com)
        - Kamal: add RAILS_HOST under env.clear in config/deploy.yml, then redeploy
        - Anything else: set the RAILS_HOST environment variable

      Details: /docs/developer/deployment (Production preflight section).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end
end

# SECRET_KEY_BASE_DUMMY marks build-time boots (the Dockerfile's
# assets:precompile), where deployment ENV is legitimately absent.
RequiredProductionConfig.check! if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"]
