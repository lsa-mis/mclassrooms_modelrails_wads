require "rails_helper"

# MiClassrooms Phase 3 Task 4 (Brief §5.2, §3.2): Find a Room's controller —
# wires RoomSearch (Task 2), CharacteristicFilterGroups (Task 3), and
# RoomPolicy (Task 1) into GET /find-a-room. DirectoryScoped resolves
# Current.workspace off TenancyConfig.shared_workspace_slug (same stubbing
# pattern as spec/requests/test_login_spec.rb and directory_scoped_spec.rb),
# so every example below runs under a single shared workspace.
RSpec.describe "GET /find-a-room", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # `create(:user)` itself triggers User#onboard_workspace (after_create),
  # which — under the :shared posture stubbed above — auto-joins `workspace`
  # with TenancyConfig.shared_join_role before this method ever runs. Creating
  # a second Membership for the same (user, workspace) pair would violate the
  # user_id/workspace_id uniqueness index, so this reuses and re-roles the
  # auto-created membership instead of inserting a new one.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  describe "unauthenticated" do
    it "redirects to sign-in instead of rendering rooms" do
      get find_a_room_path

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "as a viewer" do
    let(:viewer) { membership_with("viewer") }
    let(:building) { create(:building, workspace: workspace) }
    let!(:listed_classroom) { create(:room, building: building, workspace: workspace, facility_code: "MLB1001") }
    let!(:hidden_classroom) { create(:room, :hidden, building: building, workspace: workspace, facility_code: "MLB1002") }
    let!(:non_classroom) { create(:room, building: building, workspace: workspace, room_type: "Office", facility_code: "MLB1003") }

    before { sign_in(viewer) }

    it "returns 200 including the listed classroom, excluding hidden and non-classroom rooms" do
      get find_a_room_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(listed_classroom.display_name)
      expect(response.body).not_to include(hidden_classroom.display_name)
      expect(response.body).not_to include(non_classroom.display_name)
    end

    it "responds with the JSON shape: room keys + pagination block" do
      get find_a_room_path, as: :json

      json = response.parsed_body
      entry = json["rooms"].find { |r| r["id"] == listed_classroom.id }

      expect(entry.keys).to match_array(
        %w[id rmrecnbr facility_code display_name building capacity ada_capacity characteristics floor]
      )
      expect(entry["rmrecnbr"]).to eq(listed_classroom.rmrecnbr)
      expect(entry["facility_code"]).to eq(listed_classroom.facility_code)
      expect(entry["display_name"]).to eq(listed_classroom.display_name)
      expect(entry["building"]).to eq(building.display_name)
      expect(entry["capacity"]).to eq(listed_classroom.instructional_seat_count)
      expect(entry["ada_capacity"]).to eq(listed_classroom.ada_seat_count)
      expect(entry["characteristics"]).to eq([])
      expect(entry["floor"]).to be_nil

      expect(json["pagination"].keys).to match_array(%w[page pages count per])
    end
  end

  describe "pagination clamp" do
    let(:viewer) { membership_with("viewer") }
    let(:building) { create(:building, workspace: workspace) }

    before do
      create_list(:room, 35, building: building, workspace: workspace)
      sign_in(viewer)
    end

    it "clamps a client per above the max down to 100" do
      get find_a_room_path, params: { per: "500" }, as: :json

      expect(response.parsed_body["pagination"]["per"]).to eq(100)
    end

    it "defaults to 30 per page with 30 entries on page 1" do
      get find_a_room_path, as: :json

      json = response.parsed_body
      expect(json["pagination"]["per"]).to eq(30)
      expect(json["rooms"].size).to eq(30)
    end

    it "returns the remainder on page 2" do
      get find_a_room_path, params: { page: "2" }, as: :json

      json = response.parsed_body
      expect(json["rooms"].size).to eq(5)
      expect(json["pagination"]["page"]).to eq(2)
      expect(json["pagination"]["pages"]).to eq(2)
      expect(json["pagination"]["count"]).to eq(35)
    end
  end

  describe "view=inactive_rooms" do
    let(:building) { create(:building, workspace: workspace) }
    let!(:not_in_feed_room) { create(:room, building: building, workspace: workspace, in_feed: false) }

    it "denies a viewer with a not_authorized redirect + alert, and never leaks the inactive room" do
      viewer = membership_with("viewer")
      sign_in(viewer)

      get find_a_room_path, params: { view: "inactive_rooms" }

      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))

      follow_redirect!
      expect(response.body).not_to include(not_in_feed_room.display_name)
    end

    it "allows an admin to see the in_feed:false room" do
      admin = membership_with("admin")
      sign_in(admin)

      get find_a_room_path, params: { view: "inactive_rooms" }, as: :json

      ids = response.parsed_body["rooms"].map { |r| r["id"] }
      expect(ids).to include(not_in_feed_room.id)
    end
  end

  describe "view=inactive_buildings" do
    let(:hidden_building) { create(:building, :hidden, workspace: workspace) }
    let!(:room_in_hidden_building) { create(:room, building: hidden_building, workspace: workspace) }

    it "as admin returns 200 including a classroom in a hidden building" do
      admin = membership_with("admin")
      sign_in(admin)

      get find_a_room_path, params: { view: "inactive_buildings" }, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["rooms"].map { |r| r["id"] }
      expect(ids).to include(room_in_hidden_building.id)
    end

    it "denies a viewer" do
      viewer = membership_with("viewer")
      sign_in(viewer)

      get find_a_room_path, params: { view: "inactive_buildings" }

      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
    end
  end

  describe "view=junk" do
    let(:viewer) { membership_with("viewer") }
    let(:building) { create(:building, workspace: workspace) }
    let!(:listed_classroom) { create(:room, building: building, workspace: workspace) }

    it "behaves as the active (default) view rather than erroring or denying" do
      sign_in(viewer)

      get find_a_room_path, params: { view: "junk" }, as: :json

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["rooms"].map { |r| r["id"] }
      expect(ids).to eq([ listed_classroom.id ])
    end
  end

  # Regression guard for characteristics-filter + pagination (a common user
  # path: "show me all projector rooms" spanning several pages). RoomSearch's
  # `with_all_characteristics` merges in a GROUP BY rooms.id + HAVING relation,
  # so `.count` on it is a GROUP BY count — which returns a Hash
  # ({room_id => n}) on a bare ActiveRecord relation. Pagy 43.5.6 normalizes
  # that Hash to `.size` (the number of matching groups) internally, so
  # pagination.count/pages come out as the correct Integer and pages stay
  # disjoint. This spec pins that end-to-end contract: nothing else in the
  # suite guards it, so a future Pagy upgrade or a with_all_characteristics
  # refactor that reintroduced the raw Hash would break characteristics
  # pagination silently — here it would surface as `pagination.count` being a
  # Hash (failing the `be_a(Integer)` teeth) and page 1's slice returning all
  # 5 rooms instead of 2 (the Hash's truthy count defeating the LIMIT math).
  describe "characteristics filter + pagination" do
    let(:viewer) { membership_with("viewer") }
    let(:building) { create(:building, workspace: workspace) }
    # Already-normalized short_code: RoomSearch normalizes the query param via
    # CodeNormalizer before matching room_characteristics.short_code, so the
    # stored value must be in normalized form for the join to hit.
    let(:matching_code) { "projector" }

    let!(:matching_rooms) do
      create_list(:room, 5, building: building, workspace: workspace).each do |room|
        create(:room_characteristic, room: room, workspace: workspace, short_code: matching_code)
      end
    end

    let!(:non_matching_rooms) do
      create_list(:room, 2, building: building, workspace: workspace).each do |room|
        create(:room_characteristic, room: room, workspace: workspace, short_code: "whiteboard")
      end
    end

    before { sign_in(viewer) }

    it "paginates the grouped relation correctly: integer count, disjoint pages, no leaks" do
      seen_ids = []

      (1..3).each do |page|
        get find_a_room_path, params: { characteristics: [ matching_code ], per: "2", page: page.to_s }, as: :json
        json = response.parsed_body

        # Grouped-relation count must surface as a plain Integer, never the
        # raw GROUP BY Hash leaking through.
        expect(json["pagination"]["count"]).to be_a(Integer)
        expect(json["pagination"]["count"]).to eq(5)
        expect(json["pagination"]["pages"]).to eq(3)
        expect(json["pagination"]["per"]).to eq(2)

        page_ids = json["rooms"].map { |r| r["id"] }
        expect(page_ids & seen_ids).to be_empty # pages are disjoint
        seen_ids.concat(page_ids)
      end

      # All 5 matching rooms seen exactly once across the 3 pages; the 2
      # non-matching rooms never leaked in.
      expect(seen_ids).to match_array(matching_rooms.map(&:id))
      expect(seen_ids).not_to include(*non_matching_rooms.map(&:id))
    end
  end

  # MiClassrooms Phase 3 Task 5 (Brief §5.2): the filter form + results Turbo
  # Frame + admin view toggles. A basic render/interaction check per the task
  # brief — the comprehensive axe-AAA pass is Task 8; this only proves the
  # screen assembles (frame id, fieldset/legend groups, summary line) and that
  # a filter change narrows the SAME frame's results without a full reload.
  describe "Task 5 UI: filter form, results frame, admin toggles" do
    let(:building) { create(:building, workspace: workspace, name: "Mason Hall") }
    let!(:listed_classroom) { create(:room, building: building, workspace: workspace, facility_code: "MLB1001") }

    before do
      # A described characteristic ("Category: Value") so CharacteristicFilterGroups
      # produces a real named group — proves the fieldset/legend-per-group markup,
      # not just the "Other" catch-all a bare short_code would fall into.
      create(:room_characteristic, room: listed_classroom, workspace: workspace,
             short_code: "seating_fixed", description: "Seating: Fixed")
    end

    it "renders the results Turbo Frame with a fieldset/legend per filter group" do
      sign_in(membership_with("viewer"))

      get find_a_room_path

      expect(response.body).to include('id="find_a_room_results"')
      expect(response.body).to include("<fieldset")
      expect(response.body).to include("<legend")
      expect(response.body).to include("Seating")
    end

    it "shows the active-filter summary line when a building filter is applied" do
      sign_in(membership_with("viewer"))

      get find_a_room_path, params: { building: "Mason" }

      expect(response.body).to include(I18n.t("rooms.index.summary.building", value: "Mason"))
    end

    it "re-renders only the matching rooms when a filter narrows the result set (no full reload)" do
      other_building = create(:building, workspace: workspace, name: "Angell Hall")
      other_room = create(:room, building: other_building, workspace: workspace, facility_code: "ANG2000")
      sign_in(membership_with("viewer"))

      get find_a_room_path, params: { building: "Mason" }

      expect(response.body).to include('id="find_a_room_results"')
      expect(response.body).to include(listed_classroom.display_name)
      expect(response.body).not_to include(other_room.display_name)
    end

    it "hides the admin-only view toggles from a viewer" do
      sign_in(membership_with("viewer"))

      get find_a_room_path

      expect(response.body).not_to include(I18n.t("rooms.index.views.inactive_rooms"))
    end

    it "shows the admin-only view toggles to an admin" do
      sign_in(membership_with("admin"))

      get find_a_room_path

      expect(response.body).to include(I18n.t("rooms.index.views.inactive_rooms"))
      expect(response.body).to include(I18n.t("rooms.index.views.inactive_buildings"))
    end

    # Exercises the row branches a bare factory room never touches: a gallery
    # thumbnail (Active Storage variant), the ADA badge, a real characteristic
    # icon chip (icon_key must resolve via IconRegistry — the display_rule
    # factory's own default "wifi" isn't a real icon, so this proves the
    # happy path with one that is), and the building card. None of this is
    # covered elsewhere, so a regression here (e.g. a bad variant call) would
    # otherwise only surface in Task 8's system specs.
    it "renders a gallery thumbnail, ADA badge, characteristic icon chip, and building card" do
      listed_classroom.update!(ada_seat_count: 5)
      create(:room_gallery_image, room: listed_classroom, workspace: workspace)
      # Normalization-stable short_code: RoomCharacteristic stores the raw value
      # while CharacteristicDisplayRule normalizes via CodeNormalizer (strips
      # non-alphanumerics), so the row's icon-key join only hits when the code
      # survives normalization unchanged. "projector" does; "seating_fixed"
      # would not (the underscore is stripped to "seatingfixed").
      create(:room_characteristic, room: listed_classroom, workspace: workspace,
             short_code: "projector", description: "Media: Projector")
      create(:characteristic_display_rule, workspace: workspace, short_code: "projector", icon_key: "computer_desktop")
      sign_in(membership_with("viewer"))

      get find_a_room_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("rooms.row.ada", count: 5))
      expect(response.body).to include(I18n.t("rooms.building_card.classroom_count", count: 1))
    end

    # Teeth for the nested-interactive a11y fix: the row's characteristic icon
    # chip must give the (aria-hidden) icon a visually-hidden accessible name,
    # and the <summary> subtree must contain NO focusable/interactive descendant
    # — HTML5 forbids focusable descendants of <summary>, and axe-core's
    # nested-interactive rule (Task 8) flags exactly a `tabindex`-bearing tooltip
    # wrapper here. "Media: Projector" parses to the label "Projector" (Task 3
    # grouping); "projector" is normalization-stable so the icon-key join hits.
    it "renders the row characteristic chip with an sr-only name and no focusable element in the summary" do
      create(:room_characteristic, room: listed_classroom, workspace: workspace,
             short_code: "projector", description: "Media: Projector")
      create(:characteristic_display_rule, workspace: workspace, short_code: "projector", icon_key: "computer_desktop")
      sign_in(membership_with("viewer"))

      get find_a_room_path

      summary_html = response.body[%r{<summary\b.*?</summary>}m]
      expect(summary_html).to be_present
      expect(summary_html).to include('class="sr-only">Projector')
      # No focusable/interactive descendant of <summary>: the old ui :tooltip
      # wrapper carried tabindex="0" + role="tooltip"; the plain <span> chip does not.
      expect(summary_html).not_to include("tabindex")
      expect(summary_html).not_to include('role="tooltip"')
    end
  end
end

# MiClassrooms Phase 4 Task 3 (Brief §5.3, phase-4 plan Task 3): room detail —
# HTML + JSON, D14 conditional GET, and the hidden-room redirect. A sibling
# top-level example group (not nested in "GET /find-a-room" above) so its
# ETag-busting mutations (notes, gallery images, attachments) can't leak
# state into the Find-a-Room examples. Mirrors the same tenancy setup:
# shared-posture stub + workspace-scoped fixtures + `sign_in`.
#
# `app/views/rooms/show.html.erb` doesn't exist yet — it ships in Task 4 — so
# every example below requests `as: :json` even where the brief's language
# ("200 on a listed room") doesn't name a format; an unqualified HTML request
# would hit `respond_to`'s `format.html` branch and raise
# ActionView::MissingTemplate before Task 4 adds the view. The hidden-room
# redirect is safe to request in the default (HTML) format because it fires
# from a before_action, before the controller ever reaches `respond_to`.
RSpec.describe "GET /rooms/:id", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-show-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # Same reuse-and-re-role pattern as the Find-a-Room spec above (see that
  # file's comment): `create(:user)` auto-joins `workspace` via
  # `User#onboard_workspace` under the :shared posture stubbed here.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  let(:building) { create(:building, workspace: workspace) }
  let!(:room) { create(:room, building: building, workspace: workspace, facility_code: "MLB1001") }

  describe "as a signed-in viewer" do
    let(:viewer) { membership_with("viewer") }

    before { sign_in(viewer) }

    it "returns 200 for a listed room" do
      get room_path(room), as: :json

      expect(response).to have_http_status(:ok)
    end

    it "redirects a hidden room to Find a Room with the inactive notice" do
      hidden_room = create(:room, :hidden, building: building, workspace: workspace)

      get room_path(hidden_room)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.inactive_notice"))
    end

    # Regression guard (review fix): rooms/_media.html.erb's seating-chart
    # IMAGE branch used to reuse `rooms.show.seating_chart_link` — "Seating
    # chart for %{room} (PDF)" — as its `alt:`, falsely telling screen-reader
    # users an image attachment was a PDF. The dedicated `seating_chart_alt`
    # key (no "(PDF)" suffix) must render instead whenever the attachment's
    # content_type isn't application/pdf.
    it "renders an image seating chart's alt without the PDF suffix" do
      room.seating_chart.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "seating.png",
        content_type: "image/png"
      )

      get room_path(room)

      expect(response.body).to include(I18n.t("rooms.show.seating_chart_alt", room: room.display_name))
      expect(response.body).not_to include("(PDF)")
    end

    # MiClassrooms Phase 4 Task 8 breadcrumb retrofit: `building_path` now
    # exists, but Buildings is admin-only (BuildingPolicy denies every
    # action to a non-admin) — a viewer must NOT get a link they can't
    # follow, so the building crumb stays plain, non-interactive text for
    # them (rooms/_header.html.erb's RoleResolver branch).
    it "renders the building breadcrumb crumb as plain text, not a link" do
      get room_path(room)

      expect(response.body).not_to include(%(href="#{building_path(building)}"))
      expect(response.body).to include(building.display_name)
    end
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "returns 200 for a hidden room instead of redirecting" do
      hidden_room = create(:room, :hidden, building: building, workspace: workspace)

      get room_path(hidden_room), as: :json

      expect(response).to have_http_status(:ok)
    end

    # MiClassrooms Phase 4 Task 8 breadcrumb retrofit: an admin CAN follow
    # the building crumb (BuildingsController grants them every action), so
    # rooms/_header.html.erb renders it as a real link once building_path
    # exists.
    it "renders the building breadcrumb crumb as a link to the admin building page" do
      get room_path(room)

      expect(response.body).to include(%(href="#{building_path(building)}"))
    end
  end

  describe "conditional GET (D14)" do
    let(:viewer) { membership_with("viewer") }

    before do
      sign_in(viewer)
      # Rails' built-in ActionController::EtagWithFlash folds `flash` into the
      # ETag (so a stale cache never hides a flash message) — `sign_in`'s
      # `post session_path` leaves a "Signed in successfully." notice that
      # would otherwise survive into the FIRST request below and inflate that
      # request's ETag with flash content the second, comparison request
      # never sees (flash is one-request-lived), producing a spurious
      # mismatch unrelated to the room. This warm-up request drains it before
      # any example starts comparing ETags across two requests.
      get room_path(room), as: :json
    end

    it "returns 304 when If-None-Match matches the prior response's ETag" do
      get room_path(room), as: :json
      etag = response.headers["ETag"]
      expect(etag).to be_present

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:not_modified)
    end

    it "busts the ETag when a note on the room changes" do
      get room_path(room), as: :json
      etag = response.headers["ETag"]

      create(:note, notable: room, workspace: workspace)

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when the building's note changes" do
      get room_path(room), as: :json
      etag = response.headers["ETag"]

      create(:note, notable: building, workspace: workspace)

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when the room's contact info changes" do
      contact = create(:room_contact, room: room, workspace: workspace)

      get room_path(room), as: :json
      etag = response.headers["ETag"]

      contact.update!(scheduling_email: "new@umich.edu")

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when a gallery image is added" do
      get room_path(room), as: :json
      etag = response.headers["ETag"]

      create(:room_gallery_image, room: room, workspace: workspace)

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when a media attachment (photo) is added" do
      get room_path(room), as: :json
      etag = response.headers["ETag"]

      room.photo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "room.png",
        content_type: "image/png"
      )

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when a photo attachment is replaced" do
      room.photo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "room.png",
        content_type: "image/png"
      )

      get room_path(room), as: :json
      etag = response.headers["ETag"]

      # has_one_attached replace = purge the old attachment row + create a new
      # one (never an UPDATE-in-place), so the new row's created_at becomes
      # the new max — proving media_attachments.maximum(:created_at) tracks
      # replace, not just first-insert.
      room.photo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "room-replacement.png",
        content_type: "image/png"
      )

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when a photo attachment is removed" do
      room.photo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "room.png",
        content_type: "image/png"
      )

      get room_path(room), as: :json
      etag = response.headers["ETag"]

      # purge (not purge_later): the row must be gone before the very next
      # request. media_attachments.maximum(:created_at) drops to nil, which
      # show_last_modified's `.compact.max` already tolerates.
      room.photo.purge

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "produces a different ETag for an admin than a viewer of the same room" do
      get room_path(room), as: :json
      viewer_etag = response.headers["ETag"]

      Membership.find_by!(user: viewer, workspace: workspace).update!(role: Role.system_default!("admin"))
      # Re-signing in (rather than just re-roling and reusing the session)
      # leaves a fresh "Signed in successfully." flash — same warm-up-drain
      # concern as the outer before block, so drain it before the comparison
      # request.
      sign_in(viewer)
      get room_path(room), as: :json

      get room_path(room), as: :json
      admin_etag = response.headers["ETag"]

      expect(admin_etag).not_to eq(viewer_etag)
    end

    it "sets a private Cache-Control and never no-store" do
      get room_path(room), as: :json

      expect(response.headers["Cache-Control"]).to include("private")
      expect(response.headers["Cache-Control"]).not_to include("no-store")
    end
  end

  describe "JSON shape" do
    let(:viewer) { membership_with("viewer") }
    let(:unit) { create(:unit, workspace: workspace) }
    let(:floor) { create(:floor, building: building, workspace: workspace, label: "3") }
    let!(:full_room) do
      create(:room, building: building, workspace: workspace, unit: unit, floor: floor,
             facility_code: "MLB3001", nickname: "The Lounge", room_number: "3001",
             room_type: "Classroom", square_feet: 500,
             instructional_seat_count: 40, ada_seat_count: 2)
    end

    before do
      # Normalization-stable short_code (RoomCharacteristic#short_code is NOT
      # model-normalized, unlike CharacteristicDisplayRule#short_code, which
      # goes through CodeNormalizer — an underscore here would only matter if
      # this spec also created a matching display rule, which it doesn't).
      create(:room_characteristic, room: full_room, workspace: workspace, short_code: "projector")
      create(:room_contact, room: full_room, workspace: workspace)
      sign_in(viewer)
    end

    it "renders the full room-show JSON contract" do
      get room_path(full_room), as: :json

      json = response.parsed_body

      expect(json.keys).to match_array(
        %w[id rmrecnbr facility_code display_name nickname building floor_label room_number room_type
           square_feet instructional_seat_count ada_seat_count department characteristics media contacts url]
      )
      expect(json["id"]).to eq(full_room.id)
      expect(json["rmrecnbr"]).to eq(full_room.rmrecnbr)
      expect(json["facility_code"]).to eq(full_room.facility_code)
      expect(json["display_name"]).to eq(full_room.display_name)
      expect(json["nickname"]).to eq("The Lounge")
      expect(json["building"]).to eq(
        "id" => building.id, "name" => building.name, "abbreviation" => building.abbreviation
      )
      expect(json["floor_label"]).to eq("3")
      expect(json["room_number"]).to eq("3001")
      expect(json["room_type"]).to eq("Classroom")
      expect(json["square_feet"]).to eq(500)
      expect(json["instructional_seat_count"]).to eq(40)
      expect(json["ada_seat_count"]).to eq(2)
      expect(json["department"].keys).to match_array(%w[id description group group_description])
      expect(json["characteristics"]).to eq([ "projector" ])
      expect(json["media"].keys).to match_array(
        %w[photo_url thumbnail_url panorama_url seating_chart_url gallery_urls]
      )
      expect(json["contacts"]).to be_present
      expect(json["url"]).to eq(room_url(full_room))
    end
  end
end

# MiClassrooms Phase 4 Task 6 (Brief §5.3): the floor-plan view — authorizes
# like #show (RoomPolicy#show?) and reuses the shared
# redirect_inactive_for_non_admins before_action (now extended to
# :floor_plan), so a hidden room's non-admin redirect and an admin's 200 both
# mirror "GET /rooms/:id" above. Also pins the nil-floor redirect and
# Room.natural_room_order's same-floor room ordering. Mirrors the tenancy
# setup from the two describe blocks above: shared-posture stub +
# workspace-scoped fixtures + sign_in.
RSpec.describe "GET /rooms/:id/floor_plan", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-floor-plan-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # Same reuse-and-re-role pattern as the sibling describe blocks above.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  let(:building) { create(:building, workspace: workspace) }
  let(:floor) { create(:floor, building: building, workspace: workspace, label: "2") }
  let!(:room) { create(:room, building: building, workspace: workspace, floor: floor, facility_code: "MLB1001") }

  describe "as a signed-in viewer" do
    let(:viewer) { membership_with("viewer") }

    before { sign_in(viewer) }

    it "returns 200 for a room with a floor" do
      get floor_plan_room_path(room)

      expect(response).to have_http_status(:ok)
    end

    it "redirects to the room with the no_floor notice when the room has no floor" do
      floorless_room = create(:room, building: building, workspace: workspace, floor: nil, facility_code: "MLB1099")

      get floor_plan_room_path(floorless_room)

      expect(response).to redirect_to(room_path(floorless_room))
      expect(flash[:notice]).to eq(I18n.t("rooms.floor_plan.no_floor"))
    end

    it "redirects a hidden room to Find a Room instead of rendering" do
      hidden_room = create(:room, :hidden, building: building, workspace: workspace, floor: floor, facility_code: "MLB1098")

      get floor_plan_room_path(hidden_room)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.inactive_notice"))
    end

    # Regression guard (review fix): floor_plan.html.erb used to render
    # `@floor.plan` unconditionally through `ui :image`/`<img>`, but
    # Floor#plan's content_type validation allows PDF (Task 9's building edit
    # can attach one) — a PDF floor plan rendered a browser broken-image icon.
    # Mirrors rooms/_media.html.erb's seating-chart PDF branch: a PDF plan
    # must render as a link, never an `<img>`.
    it "renders a PDF floor plan as a link instead of an image" do
      floor.plan.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/seating_chart.pdf")),
        filename: "floor-2.pdf",
        content_type: "application/pdf"
      )

      get floor_plan_room_path(room)

      expect(response.body).to include(
        I18n.t("rooms.floor_plan.plan_pdf_link", building: building.display_name, floor: floor.label)
      )
      expect(response.body).to include(%(href="#{rails_blob_path(floor.plan, disposition: :inline)}"))
      expect(response.body).not_to include("<img")
    end

    # "B100" CASTs to 0 (SQLite CAST stops at the first non-digit character)
    # and tiebreaks alphabetically ahead of any purely-numeric label; "20" <
    # "100" numerically. Same three-case semantics documented on
    # RoomSearch::DEFAULT_ORDER's tail, which Room.natural_room_order mirrors.
    it "lists same-floor classrooms in natural room-number order" do
      lettered = create(:room, building: building, workspace: workspace, floor: floor,
                         room_number: "B100", facility_code: "MLB2001")
      low = create(:room, building: building, workspace: workspace, floor: floor,
                     room_number: "20", facility_code: "MLB2002")
      high = create(:room, building: building, workspace: workspace, floor: floor,
                      room_number: "100", facility_code: "MLB2003")

      get floor_plan_room_path(room)

      body = response.body
      lettered_index = body.index(lettered.display_name)
      low_index = body.index(low.display_name)
      high_index = body.index(high.display_name)

      expect([ lettered_index, low_index, high_index ]).to all(be_present)
      expect(lettered_index).to be < low_index
      expect(low_index).to be < high_index
    end
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "returns 200 for a hidden room's floor plan instead of redirecting" do
      hidden_room = create(:room, :hidden, building: building, workspace: workspace, floor: floor, facility_code: "MLB1097")

      get floor_plan_room_path(hidden_room)

      expect(response).to have_http_status(:ok)
    end
  end
end

# MiClassrooms Phase 4 Task 7 (Brief §5.3, §14.1): admin room editing — the
# phase's first audited mutation. Every write here must flow through
# Curation::Apply (Task 1), never a bare `@room.update`, so the ActivityLog
# examples below double as the contract's regression guard. Mirrors the
# tenancy setup from the sibling describe blocks above: shared-posture stub +
# workspace-scoped fixtures + sign_in.
RSpec.describe "GET /rooms/:id/edit", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-edit-spec-workspace", personal: false) }

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

  let(:building) { create(:building, workspace: workspace) }
  let!(:room) { create(:room, building: building, workspace: workspace, facility_code: "MLB1001") }

  describe "as a non-admin viewer" do
    it_behaves_like "an admin-only action" do
      let(:actor) { membership_with("viewer") }
      let(:http_method) { :get }
      let(:request_path) { edit_room_path(room) }
    end
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    it "returns 200 and renders the edit form" do
      sign_in(admin)

      get edit_room_path(room)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(room.display_name)
    end
  end
end

RSpec.describe "PATCH /rooms/:id", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-update-spec-workspace", personal: false) }

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

  let(:building) { create(:building, workspace: workspace) }
  let!(:room) do
    create(:room, building: building, workspace: workspace, facility_code: "MLB1001", nickname: "Old Name")
  end

  describe "as a non-admin viewer" do
    it_behaves_like "an admin-only action" do
      let(:actor) { membership_with("viewer") }
      let(:http_method) { :patch }
      let(:request_path) { room_path(room) }
      let(:request_params) { { room: { nickname: "Should not apply" } } }
    end
  end

  describe "as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    # The audit-granularity contract Curation::Apply already proves in
    # isolation (spec/lib/curation/apply_spec.rb): a real column change
    # (nickname) appears in before_after; this pins that RoomsController's
    # #update wires it correctly end-to-end, one ActivityLog per request.
    it "updates the curated field via Curation::Apply and writes exactly one audited ActivityLog" do
      expect {
        patch room_path(room), params: { room: { nickname: "New Name" } }
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room))
      expect(room.reload.nickname).to eq("New Name")

      log = ActivityLog.last
      expect(log.action).to eq("room.curated")
      expect(log.before_after).to eq(
        "before" => { "nickname" => "Old Name" }, "after" => { "nickname" => "New Name" }
      )
    end

    # Room's own `content_type: [:png, :jpeg, :webp]` validation on :photo is
    # the natural, already-existing validation reachable through this form —
    # a PDF is allowed for seating_chart but not photo, so attaching one here
    # is a genuine ActiveRecord::RecordInvalid, not a stub.
    it "re-renders :edit with 422 on a validation failure and writes no ActivityLog" do
      expect {
        patch room_path(room), params: {
          room: { photo: fixture_file_upload("seating_chart.pdf", "application/pdf") }
        }
      }.not_to change(ActivityLog, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(room.reload.photo).not_to be_attached
    end

    it "persists a gallery reorder" do
      first = create(:room_gallery_image, room: room, workspace: workspace, position: 0)
      second = create(:room_gallery_image, room: room, workspace: workspace, position: 1)

      patch room_path(room), params: {
        room: { gallery_images_attributes: {
          "0" => { id: first.id, position: "1" },
          "1" => { id: second.id, position: "0" }
        } }
      }

      expect(response).to redirect_to(room_path(room))
      expect(first.reload.position).to eq(1)
      expect(second.reload.position).to eq(0)
    end

    it "removes a gallery image via _destroy" do
      image = create(:room_gallery_image, room: room, workspace: workspace)

      expect {
        patch room_path(room), params: {
          room: { gallery_images_attributes: { "0" => { id: image.id, _destroy: "1" } } }
        }
      }.to change(RoomGalleryImage, :count).by(-1)

      expect(response).to redirect_to(room_path(room))
    end
  end

  describe "POST create" do
    it "has no route" do
      post "/rooms", params: { room: { rmrecnbr: "9999999" } }

      expect(response).to have_http_status(:not_found)
    end

    it "RoomPolicy#create? is false" do
      expect(RoomPolicy.new(nil, Room.new).create?).to be(false)
    end
  end
end
