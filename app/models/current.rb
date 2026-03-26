class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :workspace
  attribute :project

  delegate :user, to: :session, allow_nil: true
end
