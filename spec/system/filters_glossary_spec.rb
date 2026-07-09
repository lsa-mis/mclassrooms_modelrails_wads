require "rails_helper"

# MiClassrooms Phase 3 Task 8 (Brief §5.1): end-to-end coverage of the
# filters glossary — grouping (including a filterable:false display rule
# still surfacing here, unlike the live filter form) and the team_learning:
# true category override, alphabetical entry order within a group, and axe
# WCAG 2.2 AAA auditing in both themes (static page — cheap to audit both).
RSpec.describe "Filters glossary", type: :system do
  # `let`, not a top-level constant — see find_a_room_spec.rb's comment on
  # why (matches spec/system/docs_spec.rb's `axe_options` convention).
  #
  # Full conformance set (A + AA + AAA) — see find_a_room_spec.rb's comment
  # for why wcag2aaa alone is not enough.
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag2aaa" ] } } }

  # `characteristics#glossary` also runs under DirectoryScoped (Current.workspace
  # resolved by TenancyConfig.shared_workspace_slug) — same shared-posture setup
  # as find_a_room_spec.rb, and for the same reason: without it the controller's
  # before_action can't resolve a workspace at all and redirects to root.
  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, workspace: workspace) }
  let!(:room) { create(:room, building: building, workspace: workspace) }

  # Normalization-stable short_codes (lowercase, no punctuation) for the two
  # entries that need a CharacteristicDisplayRule to actually apply: only the
  # phase-2 sync normalizes RoomCharacteristic.short_code, not the model
  # itself, while CharacteristicDisplayRule force-normalizes on save — so an
  # already-normalized literal is required on BOTH sides for the short_code
  # join to hit.
  let!(:whiteboard) do
    create(:room_characteristic, room: room, short_code: "whiteboard", description: "Media: Whiteboard",
           long_description: "A standard wall-mounted whiteboard.")
  end
  let!(:internal_only) do
    create(:room_characteristic, room: room, short_code: "internalonly", description: "Media: Internal Only",
           long_description: "Not shown in the filter form, tracked for internal reference only.")
  end
  let!(:internal_only_rule) do
    create(:characteristic_display_rule, workspace: workspace, short_code: "internalonly", filterable: false)
  end
  let!(:projector) do
    create(:room_characteristic, room: room, short_code: "projector", description: "Media: Projector",
           long_description: "A ceiling-mounted projector with HDMI input.")
  end
  let!(:team_pods) do
    create(:room_characteristic, room: room, short_code: "tbl", description: "Seating: Team Pods",
           long_description: "Modular table pods designed for team-based learning activities.")
  end
  let!(:team_learning_rule) do
    create(:characteristic_display_rule, workspace: workspace, short_code: "tbl", team_learning: true)
  end

  let(:user) { create(:user) }
  before { sign_in_via_form(user) }

  it "groups characteristics by category, alphabetizes entries, honors team_learning, includes filterable:false, and shows long descriptions" do
    visit filters_glossary_path

    expect(page).to have_css("h2", text: "Media")
    expect(page).to have_css("h2", text: I18n.t("characteristics.groups.team_based_learning"))

    # team_learning: true forces the entry into "Team Based Learning" —
    # beating its parsed "Seating:" category.
    within("section", text: I18n.t("characteristics.groups.team_based_learning")) do
      expect(page).to have_content("Team Pods")
      expect(page).to have_content("Modular table pods designed for team-based learning activities.")
    end

    within("section", text: "Media") do
      # filterable: false is excluded from the live filter form's .filters,
      # but the glossary uses .glossary — which still includes it, sorted
      # alphabetically alongside the other two Media entries, not appended
      # last (it was also created FIRST here despite alphabetizing second).
      expect(page).to have_content("Internal Only")
      expect(page).to have_content("Not shown in the filter form, tracked for internal reference only.")
      expect(page).to have_content("Projector")
      expect(page).to have_content("A ceiling-mounted projector with HDMI input.")
      expect(page).to have_content("Whiteboard")
      expect(page).to have_content("A standard wall-mounted whiteboard.")

      entry_labels = all("dt").map(&:text)
      internal_index  = entry_labels.index { |t| t.include?("Internal Only") }
      projector_index = entry_labels.index { |t| t.include?("Projector") }
      whiteboard_index = entry_labels.index { |t| t.include?("Whiteboard") }

      expect(internal_index).to be < projector_index
      expect(projector_index).to be < whiteboard_index
    end

    expect(axe_violations_in_both_themes(axe_options)).to be_empty
  end
end
