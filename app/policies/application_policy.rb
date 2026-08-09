class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  # You may grant a role only if you already hold every permission it confers.
  # Guards privilege elevation (e.g. Admin→Owner, or any custom role granting a
  # permission the actor lacks). Fork invariant: the top role must stay a
  # permission superset, or actors lose the ability to assign roles that use
  # newly-added permissions. See docs/reviews security sprint (SEC-1).
  def may_grant?(role)
    return false unless membership

    role.permissions.to_h.all? { |permission, enabled| !enabled || can?(permission) }
  end

  private

  def membership
    return nil unless record_in_current_workspace?

    @membership ||= Current.workspace&.memberships&.kept&.find_by(user: user)
  end

  def can?(permission)
    membership&.role&.permissions&.dig(permission.to_s) == true
  end

  # Defense-in-depth against the cross-workspace footgun. Isolation is
  # compositional here (Tenanted installs no default_scope), so it holds only
  # while controllers resolve records through the request's workspace. If a
  # record is ever loaded unscoped and belongs to another workspace, refuse to
  # answer membership-derived permission checks — otherwise a user's role in
  # THEIR workspace would authorize action on a FOREIGN record. Records with no
  # workspace_id (the class itself on index/create, or an unsaved record) are
  # not cross-tenant risks and pass through.
  def record_in_current_workspace?
    return true unless record.respond_to?(:workspace_id)

    record_workspace_id = record.workspace_id
    return true if record_workspace_id.nil?

    record_workspace_id == Current.workspace&.id
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end
end
