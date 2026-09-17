module Operations
  class UserPolicy < BasePolicy
    def create?  = false
    def update?  = false
    def destroy? = false
    def unlock?  = operator?
    # The panel never suspends an operator — revoke the operatorship first —
    # so the last-operator arithmetic never has to run here. `rails
    # users:suspend` bypasses this, as break-glass paths do (/docs/developer/security).
    def suspend?   = operator? && !record.operator?
    def unsuspend? = operator?
  end
end
