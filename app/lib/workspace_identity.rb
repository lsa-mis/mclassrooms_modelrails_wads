class WorkspaceIdentity < Identity
  def image = model.logo
  def image_original = model.logo_original
  def source = model.logo_source
  def available_sources = model.available_logo_sources

  private

  def assign_image(file) = model.logo = file
  def assign_image_original(file) = model.logo_original = file
  def write_source(value) = model.logo_source = value
  def write_name(value) = model.name = value
end
