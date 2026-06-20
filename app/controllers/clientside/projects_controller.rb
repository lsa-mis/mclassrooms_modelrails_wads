module Clientside
  class ProjectsController < BaseController
    before_action :set_client_project, only: :show
    before_action :ensure_clientside_enabled, only: :show

    def index
      @projects = Project.where(id: Current.user.client_accesses.kept.select(:project_id))
    end

    def show
      @resources = @project.client_visible_resources
    end
  end
end
