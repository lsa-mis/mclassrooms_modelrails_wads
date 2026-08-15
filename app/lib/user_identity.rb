class UserIdentity < Identity
  def image = model.avatar
  def image_original = model.avatar_original
  def source = model.avatar_source
  def available_sources = model.available_avatar_sources

  # Nil unless "gravatar" is an actually-available source: has_gravatar is
  # written asynchronously (CheckGravatarJob), and this surface must never
  # contradict available_sources during that window.
  def gravatar_url(size: 256)
    return nil unless available_sources.include?("gravatar")
    model.gravatar_url(size: size)
  end

  private

  def assign_image(file) = model.avatar = file
  def assign_image_original(file) = model.avatar_original = file
  def write_source(value) = model.avatar_source = value
end
