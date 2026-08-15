# Value object over an OmniAuth::AuthHash (the OAuth provider's payload). Gives
# OmniauthCallbacksController a domain vocabulary — provider, email,
# email_verified? — instead of reaching into auth_hash.info/.credentials at ~10
# sites. Pure parsing; no persistence and no framework state.
class OauthIdentity
  def initialize(auth_hash)
    @auth_hash = auth_hash
  end

  def provider
    OmniauthAdapters.normalize_provider(@auth_hash.provider)
  end

  # Human-facing provider label ("Google", "GitHub") for flash copy.
  def provider_name
    Authentication.display_name_for(provider)
  end

  def uid
    @auth_hash.uid
  end

  def email
    @auth_hash.info.email
  end

  # Providers may explicitly mark the supplied email unverified (Google sets
  # info.email_verified: false for unverified accounts). Only an explicit false
  # gates — providers that don't expose the field (e.g. GitHub) are treated as
  # implicitly verified. Auto-verify / auto-link is refused when this is false,
  # since an attacker-controlled unverified account would otherwise enable
  # account takeover.
  def email_verified?
    @auth_hash.info.email_verified != false
  end

  # Fork extension (MiClassrooms, RP-initiated logout D4): the OIDC id_token,
  # handed back to Okta as id_token_hint on sign-out. Google's strategy also
  # populates credentials.id_token, so callers must gate on provider == "okta"
  # (see OmniauthCallbacksController#stash_okta_logout_state).
  def id_token
    @auth_hash.credentials&.id_token
  end

  def first_name
    @auth_hash.info.first_name.presence || @auth_hash.info.name&.split&.first || "User"
  end

  def last_name
    @auth_hash.info.last_name.presence || @auth_hash.info.name&.split&.last || "User"
  end

  # Attributes for persisting/refreshing an Authentication: OAuth credentials
  # plus the avatar URL when the provider supplies one.
  def auth_attrs
    attrs = {
      oauth_token: @auth_hash.credentials.token,
      oauth_refresh_token: @auth_hash.credentials.refresh_token,
      oauth_expires_at: @auth_hash.credentials.expires_at ? Time.at(@auth_hash.credentials.expires_at) : nil
    }
    attrs[:avatar_url] = @auth_hash.info.image if @auth_hash.info.image.present?
    attrs
  end
end
