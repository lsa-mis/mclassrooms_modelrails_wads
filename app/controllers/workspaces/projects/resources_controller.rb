module Workspaces
  module Projects
    class ResourcesController < ApplicationController
      include WorkspaceScoped
      before_action :set_project
      before_action :set_resource, only: [:show, :edit, :update, :destroy, :reposition]

      def index
        authorize Resource
        @resources = @project.resources.kept.positioned.includes(:created_by)
      end

      def new
        authorize Resource
        @type = validated_resource_type
        return unless @type
        @resource = @project.resources.build
        @resourceable = @type.constantize.new
      end

      def create
        authorize Resource
        @type = validated_resource_type
        return unless @type

        ActiveRecord::Base.transaction do
          @resourceable = @type.constantize.create!(resourceable_params)
          @resource = @project.resources.create!(
            resource_params.merge(resourceable: @resourceable, created_by: Current.user)
          )
        end
        redirect_to workspace_project_resource_path(@workspace, @project, @resource), notice: t(".success")
      rescue ActiveRecord::RecordInvalid
        @resource ||= @project.resources.build(resource_params)
        @resourceable ||= @type.constantize.new(resourceable_params)
        render :new, status: :unprocessable_entity
      end

      def show
        authorize @resource
      end

      def edit
        authorize @resource
        @resourceable = @resource.resourceable
      end

      def update
        authorize @resource
        ActiveRecord::Base.transaction do
          @resource.resourceable.update!(resourceable_params) if resourceable_params.present?
          @resource.update!(resource_params)
        end
        redirect_to workspace_project_resource_path(@workspace, @project, @resource), notice: t(".success")
      rescue ActiveRecord::RecordInvalid
        render :edit, status: :unprocessable_entity
      end

      def destroy
        authorize @resource
        @resource.discard!
        redirect_to workspace_project_resources_path(@workspace, @project), notice: t(".success")
      end

      def reposition
        authorize @resource
        @resource.update!(position: params[:resource][:position].to_i)
        head :ok
      end

      private

      def set_project
        @project = @workspace.projects.kept.find_by!(slug: params[:project_slug])
        Current.project = @project
      end

      def set_resource
        @resource = @project.resources.kept.find(params[:id])
      end

      def validated_resource_type
        type = params.dig(:resource, :type) || params[:type] || "Document"
        unless Resource::ALLOWED_RESOURCEABLE_TYPES.include?(type)
          redirect_to workspace_project_resources_path(@workspace, @project), alert: t("resources.invalid_type")
          return nil
        end
        type
      end

      def resource_params
        params.require(:resource).permit(:title, :status)
      end

      def resourceable_params
        case @type || @resource&.resourceable_type
        when "Document"
          params.fetch(:document, {}).permit(:body)
        else
          {}
        end
      end
    end
  end
end
