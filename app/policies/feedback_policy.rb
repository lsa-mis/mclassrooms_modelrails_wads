# Headless policy for the feedback surface (authorize :feedback, ...). Any
# signed-in user may send feedback — the controller already requires
# authentication; this satisfies the fork's "every action is Pundit-authorized"
# invariant and leaves a seam if feedback is ever restricted by role.
class FeedbackPolicy < ApplicationPolicy
  def new? = true

  def create? = true
end
