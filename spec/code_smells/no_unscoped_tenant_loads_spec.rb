require "rails_helper"

# Tenant isolation in this template is compositional, not ambient. `Tenanted`
# installs NO `default_scope` (see app/docs/developer/extending.md), so a
# workspace-scoped record stays in-workspace only because controllers resolve
# it THROUGH the request's workspace — `@workspace.projects.find_by!(...)`,
# never `Project.find(params[:id])`. A direct class-level single-record load
# reaches across every workspace and hands a foreign record to the policy
# layer, where a user's role in THEIR workspace can authorize action on it
# (ApplicationPolicy#can? keys off Current.workspace). ApplicationPolicy carries
# a runtime guard against that, but the guard is defense-in-depth; the load
# itself is the smell, and this spec fails the suite when one appears.
#
# Scope is deliberately narrow to stay false-positive-free:
#   * Only CONTROLLERS are scanned. Jobs/services legitimately cross workspaces
#     and establish context explicitly (a documented Tenanted exception).
#   * Only the single-record finders find / find_by / find_by! / find_by_*
#     are forbidden — the sharp footgun (load one foreign record by id/slug).
#     `.where(...)` is allowed: it returns a relation the caller must still
#     scope, and the clientside area's safe pattern is exactly
#     `Project.where(id: accessible_project_ids).find_by(slug:)`.
#
# The Tenanted model list is discovered at runtime, so a fork that adds
# `include Tenanted` to a new model is covered automatically — no edit here.
RSpec.describe "Controllers never load Tenanted records unscoped" do
  it "resolves workspace-scoped records through the request's workspace" do
    Rails.application.eager_load!
    tenant_models = ApplicationRecord.descendants.select { |m| m.include?(Tenanted) }
    expect(tenant_models).not_to be_empty, "expected at least one Tenanted model (e.g. Project)"

    controller_files = Dir.glob(Rails.root.join("app/controllers/**/*.rb"))

    violations = controller_files.each_with_object([]) do |path, acc|
      source = File.read(path)
      File.foreach(path).with_index(1) do |line, lineno|
        tenant_models.each do |model|
          # `Model.find(` / `.find_by(` / `.find_by!(` / `.find_by_slug(`.
          # Anchored on the constant, so `@workspace.projects.find_by!` (the
          # correct association-scoped form) never matches.
          next unless line =~ /\b#{Regexp.escape(model.name)}\.find(_by\w*)?!?\s*\(/
          acc << "#{path.sub("#{Rails.root}/", '')}:#{lineno}  (#{model.name} loaded unscoped)"
        end
      end
    end

    expect(violations).to be_empty, <<~MSG
      Unscoped Tenanted-record load(s) found in #{violations.size} controller location(s):

      #{violations.join("\n")}

      A class-level finder crosses every workspace. Resolve through the request's
      workspace instead so a foreign record can never be loaded:
        BAD:   Project.find_by!(slug: params[:slug])
        GOOD:  @workspace.projects.find_by!(slug: params[:slug])
      (Clientside area: scope through the client's own access, e.g.
        Project.where(id: accessible_project_ids).find_by(slug: params[:id]).)
    MSG
  end
end
