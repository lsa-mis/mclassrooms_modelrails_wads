# Deliberate deviation: a model-layer Current.* read, accepted for tenant
# ergonomics. The scope is OPT-IN — there is no default_scope, so isolation
# is never ambient: controllers must resolve records through the request's
# workspace (@workspace.projects.find_by!(...), never Project.find(id)),
# enforced by ApplicationPolicy#record_in_current_workspace? and
# spec/code_smells/no_unscoped_tenant_loads_spec.rb. See /docs/developer/extending.
module Tenanted
  extend ActiveSupport::Concern

  included do
    belongs_to :workspace
    scope :for_current_workspace, -> { where(workspace: Current.workspace) }
  end
end
