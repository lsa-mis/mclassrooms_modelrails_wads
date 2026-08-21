require "rails_helper"

RSpec.describe EnforcesProjectTool do
  let(:gated_controller) do
    Class.new(ActionController::Base) do
      include EnforcesProjectTool
      enforces_tool :docs
    end
  end

  describe ".enforces_tool" do
    it "stores the key so subclasses inherit the enforcement" do
      subclass = Class.new(gated_controller)
      expect(subclass.enforced_tool_key).to eq(:docs)
    end

    it "registers the guard callback when the tool is declared" do
      filters = gated_controller._process_action_callbacks.map(&:filter)
      expect(filters).to include(:enforce_project_tool_enabled)
    end

    it "does not register the guard on a controller that never declares a tool" do
      bare = Class.new(ActionController::Base) { include EnforcesProjectTool }
      expect(bare._process_action_callbacks.map(&:filter)).not_to include(:enforce_project_tool_enabled)
    end

    it "registers the guard after set_project in the gated resources controller" do
      filters = Workspaces::Projects::ResourcesController._process_action_callbacks.map(&:filter)
      expect(filters.index(:enforce_project_tool_enabled)).to be > filters.index(:set_project)
    end
  end
end
