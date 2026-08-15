require "rails_helper"

# Tenant isolation in this template is compositional, not ambient. `Tenanted`
# installs NO `default_scope` (see app/docs/developer/extending.md), so a
# workspace-scoped record stays in-workspace only because request-context code
# resolves it THROUGH the request's workspace — `@workspace.projects.find_by!(...)`,
# never `Project.find(params[:id])`. A direct class-level single-record load
# reaches across every workspace and hands a foreign record to the policy
# layer, where a user's role in THEIR workspace can authorize action on it
# (ApplicationPolicy#can? keys off Current.workspace). ApplicationPolicy carries
# a runtime guard against that, but the guard is defense-in-depth; the load
# itself is the smell, and this spec fails the suite when one appears.
#
# Scope (broadened for SEC-13; still deliberately false-positive-free):
#   * CONTROLLERS, HELPERS, and VIEWS are scanned — everything that runs in
#     request context, where ambient `Current.workspace` makes the footgun
#     sharp. Jobs/services/mailers stay exempt: they legitimately cross
#     workspaces and establish context explicitly (a documented Tenanted
#     exception).
#   * Forbidden: class-level single-record loads — the finders
#     find / find_by / find_by! / find_by_* / sole / find_sole_by, AND a
#     class-level `.where(...)` chained to a single-record terminal
#     (.first/.take/.sole/.last) on the same line. A bare `.where(...)` is
#     still allowed: it returns a relation the caller must scope, and the
#     clientside area's safe pattern is exactly
#     `Project.where(id: accessible_project_ids).find_by(slug:)`.
#     Known limitation: a where-chain split across lines, or a where→find_by
#     on an UNSAFE id set, is beyond a line regex — the runtime policy guard
#     remains the backstop for those.
#
# The Tenanted model list is discovered at runtime, so a fork that adds
# `include Tenanted` to a new model is covered automatically — no edit here.
RSpec.describe "Request-context code never loads Tenanted records unscoped" do
  def self.finder_pattern(model_name)
    /\b#{Regexp.escape(model_name)}\.(find(_by\w*)?!?|sole\b|find_sole_by!?)\s*[(\s]/
  end

  def self.where_single_record_pattern(model_name)
    /\b#{Regexp.escape(model_name)}\.where\b[^\n]*\.(first!?|take!?|sole|last!?)\b/
  end

  def scan_source(source, model_names)
    violations = []
    source.each_line.with_index(1) do |line, lineno|
      model_names.each do |name|
        if line.match?(self.class.finder_pattern(name)) ||
           line.match?(self.class.where_single_record_pattern(name))
          violations << [ lineno, name ]
        end
      end
    end
    violations
  end

  # Positive controls: prove the scanner catches what it claims to catch —
  # a regex that silently rots would let the real scan pass on violations.
  describe "scanner self-test" do
    it "catches class-level single-record finders" do
      %w[
        Project.find(params[:id])
        Project.find_by!(slug:\ params[:slug])
        Project.find_by_slug(params[:slug])
        Project.sole
      ].each do |bad|
        expect(scan_source("x = #{bad}\n", [ "Project" ])).not_to be_empty, "expected to catch: #{bad}"
      end
    end

    it "catches a class-level where chained to a single-record terminal" do
      [
        "Project.where(id: params[:id]).first",
        "Project.where(slug: params[:slug]).take",
        "Project.where(workspace_id: x).order(:id).last"
      ].each do |bad|
        expect(scan_source("x = #{bad}\n", [ "Project" ])).not_to be_empty, "expected to catch: #{bad}"
      end
    end

    it "allows association-scoped finders, bare relations, and the clientside pattern" do
      [
        "@workspace.projects.find_by!(slug: params[:slug])",
        "Project.where(workspace: @workspace)",
        "Project.where(id: accessible_project_ids).find_by(slug: params[:id])",
        "current_workspace.projects.first"
      ].each do |good|
        expect(scan_source("x = #{good}\n", [ "Project" ])).to be_empty, "false positive on: #{good}"
      end
    end
  end

  it "resolves workspace-scoped records through the request's workspace" do
    Rails.application.eager_load!
    tenant_models = ApplicationRecord.descendants.select { |m| m.include?(Tenanted) }
    expect(tenant_models).not_to be_empty, "expected at least one Tenanted model (e.g. Project)"
    model_names = tenant_models.map(&:name)

    request_context_files =
      Dir.glob(Rails.root.join("app/controllers/**/*.rb")) +
      Dir.glob(Rails.root.join("app/helpers/**/*.rb")) +
      Dir.glob(Rails.root.join("app/views/**/*.erb"))

    violations = request_context_files.each_with_object([]) do |path, acc|
      scan_source(File.read(path), model_names).each do |lineno, name|
        acc << "#{path.sub("#{Rails.root}/", '')}:#{lineno}  (#{name} loaded unscoped)"
      end
    end

    expect(violations).to be_empty, <<~MSG
      Unscoped Tenanted-record load(s) found in #{violations.size} request-context location(s):

      #{violations.join("\n")}

      A class-level finder crosses every workspace. Resolve through the request's
      workspace instead so a foreign record can never be loaded:
        BAD:   Project.find_by!(slug: params[:slug])
        BAD:   Project.where(slug: params[:slug]).first
        GOOD:  @workspace.projects.find_by!(slug: params[:slug])
      (Clientside area: scope through the client's own access, e.g.
        Project.where(id: accessible_project_ids).find_by(slug: params[:id]).)
    MSG
  end
end
