module Operations
  # Deliberately NOT an ApplicationPolicy: that class derives every answer from
  # a kept membership in Current.workspace and refuses foreign records
  # (record_in_current_workspace?). The operations area has no current
  # workspace and no membership; its one question is "does this user operate
  # the instance?". Teaching ApplicationPolicy about operators would re-permit
  # every existing policy for them on the next fork merge.
  class BasePolicy
    attr_reader :user, :record

    def initialize(user, record)
      @user = user
      @record = record
    end

    def index?   = operator?
    def show?    = operator?
    def create?  = operator?
    def new?     = create?
    def update?  = operator?
    def edit?    = update?
    def destroy? = operator?

    private

    def operator?
      user.present? && user.operator?
    end
  end
end
