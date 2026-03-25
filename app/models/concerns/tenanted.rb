module Tenanted
  extend ActiveSupport::Concern

  included do
    belongs_to :workspace
    scope :for_current_workspace, -> { where(workspace: Current.workspace) }
  end
end
