# What a workspace's icon shows — the fallback chain logo → owner's uploaded
# avatar (personal workspaces only; helper-level composition of two identities
# per the CTRL-1 design's non-goals) → initials — answered as UI::AvatarComponent
# args. Extracted from WorkspaceHelper (#654) so the chain is a directly-testable
# unit; rendering stays in the one-line WorkspaceIconHelper.
class WorkspaceIcon
  def initialize(workspace, size:)
    @workspace = workspace
    @size = size
  end

  # The block resolves upload variants to URLs (main_app.url_for — route
  # context the view supplies); see Identity#image_url.
  #
  # image? is probed BEFORE image_url and unconditionally: reading the
  # attachment per row keeps callers' logo_attachment eager loads "used"
  # (Bullet flags an untouched includes suite-wide), exactly as the
  # pre-extraction helper did. Source dispatch still belongs to image_url —
  # an inconsistent row (attachment present, non-upload source) renders
  # initials, which is what the write path's purge invariant implies.
  def avatar_args(&variant_url)
    if identity.image? && (url = identity.image_url(size: px, &variant_url))
      image_args(url, identity)
    elsif owner_identity&.uploaded_image?
      image_args(owner_identity.image_url(size: px, &variant_url), owner_identity)
    else
      { fallback: identity.initials, hue: identity.custom_hue, size: size }
    end
  end

  private

  attr_reader :workspace, :size

  def identity = @identity ||= workspace.identity

  def owner_identity
    return nil unless workspace.personal?

    @owner_identity ||= workspace.owner&.identity
  end

  def px = AvatarHelper::AVATAR_SIZES.fetch(size)[:px]

  # src + fallback together arm the component's broken-image swap (#756) — an
  # image that 404s recovers to initials in the owning identity's hue.
  def image_args(url, image_identity)
    { src: url, fallback: image_identity.initials, hue: image_identity.custom_hue, size: size }
  end
end
