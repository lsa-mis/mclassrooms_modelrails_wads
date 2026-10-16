# frozen_string_literal: true

require "rails_helper"
require "action_view/herb_checker"
require "tmpdir"

# Runs `bin/rails herb:check`'s checker on every PR, and the same compile over Lookbook previews, Turbo
# Streams and public/ pages, so a mismatched tag or unsafe ERB output fails here instead of in a browser.
RSpec.describe "Code smell: templates compile through Herb" do
  let(:view_paths) { ActionController::Base.view_paths.select { |resolver| resolver.respond_to?(:all_unbound_templates) } }
  # Under app/, not Rails.root: CI bundles gems into vendor/bundle inside the repo.
  let(:app_paths) { view_paths.select { |resolver| resolver.path.to_s.start_with?("#{Rails.root.join('app')}/") } }
  let(:app_templates_written_against) { 185 }
  let(:spec_paths) { %w[spec/components/previews spec/support/harness/views].map { |dir| ActionView::FileSystemResolver.new(Rails.root.join(dir)) } }
  let(:spec_templates_written_against) { 290 }
  let(:streams_written_against) { 7 }
  let(:static_pages) { Dir[Rails.root.join("public/*.html")] }
  let(:static_pages_written_against) { 5 }

  # A gem's template that fails, with the issue tracking it upstream; an entry that starts compiling fails below.
  let(:known_gem_failures) { { "biscuit-rails" => "biscuit/banner/_banner.html.erb (#1341, garethfr/biscuit-rails#5)" } }

  def html_erb_templates(resolvers)
    resolvers.flat_map(&:all_unbound_templates).select { |template| template.format == :html && template.handler == :erb }
  end

  def failures(resolvers)
    ActionView::HerbChecker.check(resolvers).map do |failure|
      "#{failure.template.short_identifier}: #{failure.error.message.lines.first.strip}"
    end
  end

  def stream_templates(resolvers)
    resolvers.flat_map(&:all_unbound_templates).select { |template| template.format == :turbo_stream && template.handler == :erb }
  end

  # HerbChecker reads only the html format; a Turbo Stream template carries HTML too, so it compiles the same way.
  def stream_failures(resolvers)
    handler = ActionView::Template::Handlers::ERB.new
    stream_templates(resolvers).filter_map do |unbound|
      template = unbound.bind_locals([])
      handler.call(template, template.source, implementation: ActionView::Template::Handlers::ERB::Herb,
        validate_ruby: true, visitors: [ ::Herb::Engine::Validators::SecurityValidator.new ])
      nil
    rescue ::Herb::Engine::CompilationError, ::Herb::Engine::SecurityError => error
      "#{template.short_identifier}: #{error.message.lines.first.strip}"
    end
  end

  def static_page_errors(paths)
    paths.filter_map do |path|
      error = Herb.parse(File.read(path)).errors.first
      "#{path.delete_prefix("#{Rails.root}/")}: #{error.message}" if error
    end
  end

  def gem_name(identifier) = identifier[%r{/gems/([a-z_-]+)-\d}, 1]

  it "reads every app template (floor)" do
    expect(html_erb_templates(app_paths).size).to be >= app_templates_written_against
  end

  it "compiles every app template" do
    expect(failures(app_paths)).to be_empty
  end

  it "compiles every gem template except the reviewed failures, and each of those still fails" do
    failing_gems = failures(view_paths - app_paths).map { |failure| gem_name(failure) }

    expect(failing_gems - known_gem_failures.keys).to be_empty
    expect(known_gem_failures.keys - failing_gems).to be_empty, "these gems' templates compile now; remove them from known_gem_failures"
  end

  it "compiles every Lookbook preview and spec harness template" do
    expect(html_erb_templates(spec_paths).size).to be >= spec_templates_written_against
    expect(failures(spec_paths)).to be_empty
  end

  it "compiles every Turbo Stream template" do
    expect(stream_templates(app_paths).size).to be >= streams_written_against
    expect(stream_failures(app_paths)).to be_empty
  end

  it "parses every static page in public/" do
    expect(static_pages.size).to be >= static_pages_written_against
    expect(static_page_errors(static_pages)).to be_empty
  end

  it "catches a mismatched tag, an unclosed element and ERB output in attribute position (positive control)" do
    planted = {
      "mismatched" => "<div><p>hi</div>",
      "unclosed" => "<section><p>hi</p>",
      "attribute_position" => %(<div <%= "class=x" %>>hi</div>),
      "well_formed" => "<div><p>hi</p></div>"
    }

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "planted"))
      planted.each { |name, source| File.write(File.join(dir, "planted", "_#{name}.html.erb"), source) }

      File.write(File.join(dir, "planted", "_mismatched_stream.turbo_stream.erb"), "<turbo-stream><template><p>hi</div></template></turbo-stream>")
      File.write(File.join(dir, "mismatched_page.html"), "<main><p>hi</main>")
      resolver = ActionView::FileSystemResolver.new(dir)

      caught = failures([ resolver ]).map { |failure| failure[%r{planted/_(\w+)}, 1] }
      expect(caught).to contain_exactly("mismatched", "unclosed", "attribute_position")
      expect(stream_failures([ resolver ]).size).to eq(1)
      expect(static_page_errors([ File.join(dir, "mismatched_page.html") ]).size).to eq(1)
    end
  end
end
