require "rails_helper"

# The settings layout (app/views/layouts/settings.html.erb) already applies
# py-8 (32px top/bottom) to its shared <main>. A settings sub-page that adds
# its own py-*/pt-* wrapper compounds on top of that, silently doubling or
# tripling the header-to-content gap — this exact bug shipped on all 8
# settings pages (32px -> 64-96px effective) before being caught by eye
# during a header-spacing design review, not by CI. This spec keeps it
# caught by CI going forward.
RSpec.describe "Settings page top-level padding" do
  let(:settings_view_files) do
    Dir[Rails.root.join("app/views/settings/**/*.html.erb")].reject { |f| File.basename(f).start_with?("_") }
  end

  it "does not redundantly re-add vertical padding the settings layout already provides" do
    offenders = settings_view_files.filter_map do |file|
      content = File.read(file)
      first_wrapper = content[/<(?:div|section)\b[^>]*class="[^"]*"/m]
      next unless first_wrapper&.match?(/\bp[ty]?-\d+\b/)

      relative = file.delete_prefix("#{Rails.root}/")
      "#{relative}: #{first_wrapper[/class="[^"]*"/]}"
    end

    expect(offenders).to be_empty,
      "expected no settings sub-page to add its own top-level py-*/pt-* wrapper class — " \
      "app/views/layouts/settings.html.erb's <main> already applies py-8. Redundant " \
      "padding compounds silently (32px -> 64-96px observed). Found:\n#{offenders.join("\n")}"
  end
end
