require "rails_helper"

# Find a Room redesign (2026-07 design sprint, approved direction): a compact
# filter card — one merged search box (`q`), always-visible minimum capacity,
# promoted "popular features" chips — with the characteristic long tail behind
# a native <details> "More filters" disclosure; count/sort header INSIDE the
# results Turbo frame (so live feedback survives scrolling); removable
# applied-filter chips; buildings grid dropped. Same tenancy stubbing pattern
# as spec/requests/rooms_spec.rb.
RSpec.describe "GET /find-a-room (redesigned filter card)", type: :request do
  include ClassroomBuilders

  let(:workspace) { create(:workspace, slug: "redesign-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  let(:viewer)   { membership_with("viewer") }
  let(:building) { create(:building, workspace: workspace, name: "Mason Hall") }
  let(:floor)    { create(:floor, building: building, label: "1") }
  let!(:room)    { classroom(building, "1401", 45, codes: %w[projdigit whtbrd blackout], floor: floor) }

  before { sign_in(viewer) }

  def page
    Capybara.string(response.body)
  end

  it "renders one merged search box instead of separate building/room inputs" do
    get find_a_room_path

    expect(page).to have_css("input[name='q']")
    expect(page).to have_no_css("input[name='building']")
    expect(page).to have_no_css("input[name='room']")
  end

  it "keeps minimum capacity always visible and tucks maximum capacity behind More filters" do
    get find_a_room_path

    expect(page).to have_css("input[name='capacity_min']")
    # visible: :all — the point is DOM placement behind the (closed) disclosure
    expect(page).to have_css("details#more_filters input[name='capacity_max']", visible: :all)
  end

  # A `max=` on these inputs makes form.requestSubmit() FAIL constraint
  # validation silently for over-bound values — typing 9999 froze every
  # subsequent live filter change (verified in-browser). An over-bound minimum
  # should return an honest "0 rooms found" instead.
  it "leaves capacity inputs unclamped so over-bound values get zero results, not a blocked submit" do
    get find_a_room_path

    expect(page).to have_css("input[name='capacity_min']:not([max])")
    expect(page).to have_css("details#more_filters input[name='capacity_max']:not([max])", visible: :all)
  end

  it "promotes popular features as chips outside the disclosure, without duplicating them inside" do
    get find_a_room_path

    expect(page).to have_css("input[type='checkbox'][name='characteristics[]'][value='projdigit']")
    expect(page).to have_no_css("details#more_filters input[value='projdigit']", visible: :all)
    # the long tail stays inside the disclosure
    expect(page).to have_css("details#more_filters input[type='checkbox'][name='characteristics[]'][value='blackout']", visible: :all)
  end

  it "moves the unit select into More filters and drops the per-page select" do
    get find_a_room_path

    expect(page).to have_css("details#more_filters select[name='unit_id']", visible: :all)
    expect(page).to have_no_css("select[name='per']", visible: :all)
  end

  it "puts the sort select inside the results frame, associated with the filter form" do
    get find_a_room_path

    expect(page).to have_css("turbo-frame#find_a_room_results select[name='sort'][form='find_a_room_form']")
  end

  it "renders applied filters as removable chip links inside the results frame" do
    get find_a_room_path(q: "Mason", capacity_min: "40")

    frame = page.find("turbo-frame#find_a_room_results")
    expect(frame).to have_link(I18n.t("rooms.index.summary.query", value: "Mason"))
    remove_query = frame.find_link(I18n.t("rooms.index.summary.query", value: "Mason"))["href"]
    expect(remove_query).not_to include("q=")
    expect(remove_query).to include("capacity_min=40")
  end

  it "no longer renders the buildings card grid" do
    get find_a_room_path

    expect(page).to have_no_css("turbo-frame#find_a_room_results aside")
  end

  it "gives the filter card a titled header with its own reset link, and a page subtitle" do
    get find_a_room_path(q: "Mason")

    form = page.find("form#find_a_room_form")
    expect(form).to have_text(I18n.t("rooms.filters.card_title"))
    expect(form).to have_link(I18n.t("rooms.filters.reset"))
    expect(page).to have_text(I18n.t("rooms.index.subtitle"))
  end

  it "labels the chips-row reset as Clear all" do
    get find_a_room_path(q: "Mason")

    expect(page.find("turbo-frame#find_a_room_results")).to have_link(I18n.t("rooms.filters.clear_all"))
  end

  it "counts panel-only filters on the More-filters summary, ignoring promoted chips" do
    get find_a_room_path(characteristics: %w[blackout projdigit], capacity_max: "100")

    expect(response.body).to include(I18n.t("rooms.filters.applied_count", count: 2))
    expect(response.body).not_to include(I18n.t("rooms.filters.applied_count", count: 3))
  end

  it "renders card meta as building · floor and splits the capacity number from its label" do
    get find_a_room_path

    card = page.find("turbo-frame#find_a_room_results li", match: :first)
    expect(card).to have_text("Mason Hall · 1")
    expect(card).to have_text("45")
    expect(card).to have_text(I18n.t("rooms.row.seats_label", count: 45))
  end

  describe "admin inactive views" do
    let(:admin) { membership_with("admin") }

    it "banners the inactive scope with a way back to the active view" do
      sign_in(admin)
      get find_a_room_path(view: "inactive_rooms")

      expect(response.body).to include(I18n.t("rooms.index.inactive_view_notice.inactive_rooms"))
      expect(page.find("turbo-frame#find_a_room_results"))
        .to have_link(I18n.t("rooms.index.inactive_view_notice.back_to_active"))
    end

    it "shows no banner on the active view" do
      sign_in(admin)
      get find_a_room_path

      expect(response.body).not_to include(I18n.t("rooms.index.inactive_view_notice.back_to_active"))
    end
  end
end
