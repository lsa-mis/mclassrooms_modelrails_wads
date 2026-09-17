module Operations
  class ActivityLogPolicy < BasePolicy
    def show?    = false
    def create?  = false
    def update?  = false
    def destroy? = false
  end
end
