module Operations
  class WorkspacePolicy < BasePolicy
    # create?/new? are stated explicitly, same as the refused verbs below,
    # even though they only repeat BasePolicy's inherited `operator?` answer —
    # this policy's whole job is to say what an operator may do to a
    # workspace, and leaving two of the six verbs implicit reads as an
    # oversight rather than a decision.
    def create?    = operator?
    def new?       = operator?
    def update?    = false
    def destroy?   = false
    def suspend?   = operator?
    def unsuspend? = operator?
  end
end
