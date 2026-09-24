require "rails_helper"

RSpec.describe WorkspaceSwitcherHelper, type: :helper do
  # These examples call the preloading helpers directly and never render, so
  # Bullet sees the chip's logo/role includes as an unused eager-load. The
  # includes are load-bearing in the real render; it is the absence of a render
  # that is unusual here.
  shared_context "helper call without a render" do
    around do |example|
      if defined?(Bullet) && Bullet.enable?
        original = Bullet.unused_eager_loading_enable?
        Bullet.unused_eager_loading_enable = false
        begin
          example.run
        ensure
          Bullet.unused_eager_loading_enable = original
        end
      else
        example.run
      end
    end
  end

  # #931: the switcher listed a workspace the user had been removed from,
  # offering a chip that led straight into the refusal loop.
  describe "#switcher_workspaces" do
    let(:user) { create(:user) }

    before do
      allow(Current).to receive(:user).and_return(user)
    end

    # The helper eager-loads the chip's logo and role for the header render.
    include_context "helper call without a render"

    it "omits a workspace whose membership was deactivated and keeps the active one" do
      active = create(:workspace, name: "Active Org")
      removed = create(:workspace, name: "Removed Org")
      create(:membership, :owner, user: user, workspace: active)
      create(:membership, user: user, workspace: removed).deactivate!

      expect(helper.switcher_workspaces).to include(active)
      expect(helper.switcher_workspaces).not_to include(removed)
    end
  end
  # #1091: this list was a 159-character line inside the partial, so the cap and
  # the recency order had no reachable seam and no coverage. Every request example
  # ran with two workspaces, where `.first(5)` is a no-op.
  describe "#switcher_menu_workspaces" do
    let(:user) { create(:user) }

    before { allow(Current).to receive(:user).and_return(user) }

    include_context "helper call without a render"

    # Six, so the cap does something. Access times ascending by name, and two
    # left unaccessed so the alphabetical tiebreak is exercised too.
    def build_six
      %w[Alpha Bravo Charlie Delta Echo Foxtrot].each_with_index.map do |name, i|
        workspace = create(:workspace, name: name)
        membership = create(:membership, :owner, user: user, workspace: workspace)
        membership.update_column(:last_accessed_at, i < 4 ? (i + 1).hours.ago : nil)
        workspace
      end
    end

    it "shows the five most recently used, most recent first" do
      build_six
      shown = helper.switcher_menu_workspaces(helper.switcher_workspaces, current: nil, capped: true)

      # Accessed ones first, newest access first. Alpha was accessed an hour ago
      # and Delta four hours ago, so Alpha leads.
      expect(shown.size).to eq(5)
      expect(shown.map(&:name).first(4)).to eq(%w[Alpha Bravo Charlie Delta])
    end

    it "falls back to alphabetical for workspaces never accessed" do
      build_six
      shown = helper.switcher_menu_workspaces(helper.switcher_workspaces, current: nil, capped: true)

      # Four accessed workspaces lead, so exactly one unaccessed slot is left and
      # it goes to the alphabetically first. Derived rather than hard-coded: the
      # user factory also creates a personal workspace, whose name comes from a
      # generated first name and can sort anywhere.
      accessed = shown.first(4)
      unaccessed = (helper.switcher_workspaces.to_a - accessed).map(&:name).sort

      expect(shown.last.name).to eq(unaccessed.first)
    end

    it "pins the current workspace first and never lists it twice" do
      six = build_six
      current = six.last # Foxtrot, never accessed — would not make the cap on its own
      shown = helper.switcher_menu_workspaces(helper.switcher_workspaces, current: current, capped: true)

      expect(shown.first).to eq(current)
      expect(shown.map(&:id).tally.values).to all(eq(1))
      expect(shown.size).to eq(5)
    end

    it "returns the collection untouched when not capped" do
      build_six
      all = helper.switcher_workspaces
      expect(helper.switcher_menu_workspaces(all, current: nil, capped: false)).to eq(all)
    end
  end
end
