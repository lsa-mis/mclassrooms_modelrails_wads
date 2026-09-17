module Operations
  class OperatorshipPolicy < BasePolicy
    def show?    = false
    def update?  = false
    # create?/destroy? are stated explicitly, same as Operations::WorkspacePolicy —
    # even though they only repeat BasePolicy's inherited `operator?` answer,
    # leaving live verbs implicit reads as an oversight rather than a decision.
    def create?  = operator?
    def destroy? = operator?
  end
end
