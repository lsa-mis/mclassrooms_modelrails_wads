class CheckGravatarJob < ApplicationJob
  queue_as :default

  def perform(user)
    has_gravatar = GravatarService.check(user.email_address)
    user.update_columns(has_gravatar: has_gravatar, updated_at: Time.current)
  end
end
