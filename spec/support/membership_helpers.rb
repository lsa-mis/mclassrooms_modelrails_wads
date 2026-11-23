# frozen_string_literal: true

# Adds a member to a workspace in one line; pass a membership-factory trait (:owner, :admin) as the role.
module MembershipHelpers
  def add_member(workspace, role: nil, user: create(:user))
    create(:membership, *[ role ].compact, user: user, workspace: workspace)
  end
end

RSpec.configure do |config|
  config.include MembershipHelpers
end
