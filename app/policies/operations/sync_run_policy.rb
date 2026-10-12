module Operations
  class SyncRunPolicy < BasePolicy
    def resume?  = operator?
    def update?  = false
    def destroy? = false
  end
end
