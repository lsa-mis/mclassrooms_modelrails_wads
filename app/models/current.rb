class Current < ActiveSupport::CurrentAttributes
  # Raised when tenant-scoped work begins without workspace context established.
  class NoWorkspaceError < StandardError; end

  attribute :session
  attribute :workspace

  delegate :user, to: :session, allow_nil: true

  # Fail-loud accessor for call sites that require a workspace — jobs, rake
  # tasks, any future non-browser entry point. Outside the request cycle
  # nothing establishes workspace context automatically, and a forgotten nil
  # in a where-clause silently widens a query to every tenant; this raises
  # instead.
  def workspace!
    workspace || raise(NoWorkspaceError,
      "Current.workspace is not set — establish workspace context before " \
      "tenant-scoped work (see /docs/developer/extending, Outside the request cycle)")
  end
end
