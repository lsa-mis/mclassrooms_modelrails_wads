# frozen_string_literal: true

require "rails_helper"

# Theme resolution is defined once, in the inline pre-paint script (#624); the
# controller calls window.ModelRails.themeIsDark.
RSpec.describe "Code smell: theme resolution has one home" do
  let(:script) { File.read(Rails.root.join("app/views/shared/_theme_script.html.erb")) }
  let(:controller) { File.read(Rails.root.join("app/javascript/controllers/theme_controller.js")) }

  # Whoever holds the media query decides what "dark" means; exactly one file may.
  let(:media_query) { "prefers-color-scheme: dark" }

  it "defines the resolver in the pre-paint script" do
    expect(script).to include(media_query)
    expect(script).to match(/window\.ModelRails\.themeIsDark\s*=\s*function/),
      "the inline script should DEFINE themeIsDark — it is the only copy"
  end

  it "leaves the controller with no second definition" do
    expect(controller).not_to include(media_query),
      "theme_controller.js names the media query again, which is a second answer to " \
      "'should this be dark'. It drifts silently, because a disagreement is only visible " \
      "in the window before Stimulus boots. Call window.ModelRails.themeIsDark instead."
    expect(controller).to include("window.ModelRails.themeIsDark"),
      "the controller should read the shared definition"
  end

  # The controller assumes the script ran, so every layout using it renders it.
  it "renders the script in every layout that instantiates the theme controller" do
    layouts = Dir[Rails.root.join("app/views/layouts/**/*.html.erb")]
    head_partial = File.read(Rails.root.join("app/views/shared/_layout_head.html.erb"))

    offenders = layouts.reject do |path|
      source = File.read(path)
      next true unless source.include?(%(data-controller="theme"))

      source.include?("theme_script") ||
        (source.include?("layout_head") && head_partial.include?("theme_script"))
    end.map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty, <<~MSG
      These layouts instantiate the `theme` controller without rendering
      shared/_theme_script, so `window.ModelRails.themeIsDark` will not exist
      and the controller will raise on connect:

        #{offenders.join("\n  ")}
    MSG
  end

  # POSITIVE CONTROL: a scan that matches nothing asserts nothing.
  it "finds the layouts it is scanning" do
    wired = Dir[Rails.root.join("app/views/layouts/**/*.html.erb")]
      .select { |path| File.read(path).include?(%(data-controller="theme")) }

    expect(wired.size).to be >= 5,
      "expected the app's main layouts to instantiate the theme controller; found #{wired.size}"
  end
end
