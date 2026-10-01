# frozen_string_literal: true

# Request specs stub the :shared tenancy posture, so create(:user) already joined `workspace`;
# these re-role that membership. An editor is a viewer plus an EditorAssignment (RoleResolver#editor?).
module SharedWorkspaceRoles
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  def editor_for(unit)
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: unit)
    user
  end

  # Assigned on a fresh unit, unrelated to whatever record the example is about.
  def editor_actor
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: create(:unit, workspace: workspace))
    user
  end

  def page = Capybara.string(response.body)
end

RSpec.configure do |config|
  config.include SharedWorkspaceRoles, type: :request
end
