# frozen_string_literal: true

require "rails_helper"

# The settings shell is a per-controller opt-in (`layout "settings"`), and it
# has now been forgotten three times (#562's original gap, the sessions page
# fixed by #723, the password pages fixed by #722). Per the second-bug-of-class
# rule this spec is the consolidation: any settings controller that renders
# page templates either declares the layout, renders explicitly layout-free
# (`layout: false` — modal/frame endpoints), or carries a reviewed standalone
# ruling below WITH its reason.
RSpec.describe "Settings controllers opt into the settings shell" do
  # (Locals, not constants — the no-Object-level-spec-constants guard.)
  let(:page_templates) { %w[index show new edit] }

  # Reviewed standalone rulings (#722) — each entry names its reason; delete
  # an entry if its page joins the shell.
  let(:standalone_rulings) do
    {
      # The notification inbox is a full-width triage surface reached from the
      # user menu bell; the settings sidebar's "Notifications" item points at
      # notification PREFERENCES (which has the shell). Deliberate.
      "notifications" => "triage inbox, not a sidebar destination"
    }
  end

  it "every settings controller with page templates declares the layout or a reviewed ruling" do
    offenders = Dir[Rails.root.join("app/views/settings/*")].filter_map do |dir|
      next unless File.directory?(dir)

      name = File.basename(dir)
      next if standalone_rulings.key?(name)
      next unless page_templates.any? { |t| File.exist?(File.join(dir, "#{t}.html.erb")) }

      controller = Rails.root.join("app/controllers/settings/#{name}_controller.rb")
      next unless File.exist?(controller)

      source = File.read(controller)
      name unless source.match?(/layout\s+"settings"/) || source.include?("layout: false")
    end

    expect(offenders).to be_empty,
      "settings controllers rendering pages OUTSIDE the shell (add `layout \"settings\"`, " \
      "an explicit `layout: false`, or a reviewed ruling in this spec): #{offenders.sort.inspect}"
  end
end
