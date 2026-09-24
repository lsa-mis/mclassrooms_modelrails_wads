# frozen_string_literal: true

require "rails_helper"

# Theme resolution is defined once, in the inline pre-paint script (#624).
#
# It cannot live in the Stimulus controller: importmap modules are deferred, so
# a module-side answer arrives after first paint and the page flashes the wrong
# theme. It therefore lived in BOTH places, and the failure mode of that is
# nasty — if the two disagree, the difference is only visible in the window
# before Stimulus boots, which no spec was watching and no user can report
# precisely.
#
# So the script defines `window.ModelRails.themeIsDark` and the controller
# calls it. That makes the controller depend on the script having run, which is
# only safe if every page running the controller also renders the script — the
# third example is what keeps that true.
RSpec.describe "Code smell: theme resolution has one home" do
  let(:script) { File.read(Rails.root.join("app/views/shared/_theme_script.html.erb")) }
  let(:controller) { File.read(Rails.root.join("app/javascript/controllers/theme_controller.js")) }

  # The media query string is the tell: whoever holds it is deciding what
  # "dark" means. Exactly one file may.
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

  # The controller assumes the script already ran. That holds because both come
  # from shared/_layout_head — but a new layout could wire the controller up
  # without it, and the symptom would be a JS error on that page only.
  it "renders the script in every layout that instantiates the theme controller" do
    layouts = Dir[Rails.root.join("app/views/layouts/**/*.html.erb")]
    head_partial = File.read(Rails.root.join("app/views/shared/_layout_head.html.erb"))

    offenders = layouts.reject do |path|
      source = File.read(path)
      next true unless source.include?(%(data-controller="theme"))

      # Either directly, or via the shared head partial that renders it.
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

  # A scan that matches nothing asserts nothing — pin that it sees the layouts
  # that do wire the controller up.
  it "finds the layouts it is scanning" do
    wired = Dir[Rails.root.join("app/views/layouts/**/*.html.erb")]
      .select { |path| File.read(path).include?(%(data-controller="theme")) }

    expect(wired.size).to be >= 5,
      "expected the app's main layouts to instantiate the theme controller; found #{wired.size}"
  end
end
