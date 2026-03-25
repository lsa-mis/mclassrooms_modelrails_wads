default_roles = {
  owner:  { name: "Owner",  permissions: { manage_workspace: true, manage_members: true, manage_teams: true, manage_settings: true } },
  admin:  { name: "Admin",  permissions: { manage_members: true, manage_teams: true, manage_settings: true } },
  member: { name: "Member", permissions: { manage_teams: true } },
  viewer: { name: "Viewer", permissions: {} }
}

default_roles.each do |slug, attrs|
  Role.find_or_create_by!(slug: slug.to_s, workspace_id: nil) do |r|
    r.name = attrs[:name]
    r.permissions = attrs[:permissions]
  end
end
