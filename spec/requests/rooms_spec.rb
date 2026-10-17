require "rails_helper"

RSpec.describe "GET /rooms", type: :request do
  it "redirects to Find a Room" do
    get "/rooms"
    expect(response).to redirect_to("/find-a-room")
  end
end

RSpec.describe "GET /find-a-room", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
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
      expect(response.body).to include("#{listed_classroom.room_number} #{listed_classroom.building.display_name}")
      # Full card titles: a bare 4-digit room number collides with digits in rmrecnbr links.
      hidden_title = "#{hidden_classroom.room_number} #{hidden_classroom.building.display_name}"
      non_classroom_title = "#{non_classroom.room_number} #{non_classroom.building.display_name}"
      expect(response.body).not_to include(hidden_title)
      expect(response.body).not_to include(non_classroom_title)
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

  describe "the find_a_room_page banner" do
    let(:viewer) { membership_with("viewer") }

    before { sign_in(viewer) }

    it "renders the find_a_room_page announcement's body" do
      create(:announcement, workspace: workspace, slot: "find_a_room_page", body: "Room finder tips")

      get find_a_room_path

      expect(response.body).to include("Room finder tips")
      expect(response.body).to include(I18n.t("announcements.banner.aria_label"))
    end

    it "renders nothing when no find_a_room_page announcement exists" do
      get find_a_room_path

      expect(response.body).not_to include(I18n.t("announcements.banner.aria_label"))
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

      expect(response).to redirect_to(find_a_room_path)
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

      expect(response).to redirect_to(find_a_room_path)
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

  # with_all_characteristics groups, so .count is a Hash; this pins that Pagy still pages it.
  describe "characteristics filter + pagination" do
    let(:viewer) { membership_with("viewer") }
    let(:building) { create(:building, workspace: workspace) }
    # Stored normalized: RoomSearch normalizes the query before matching short_code.
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

        expect(json["pagination"]["count"]).to be_a(Integer)
        expect(json["pagination"]["count"]).to eq(5)
        expect(json["pagination"]["pages"]).to eq(3)
        expect(json["pagination"]["per"]).to eq(2)

        page_ids = json["rooms"].map { |r| r["id"] }
        expect(page_ids & seen_ids).to be_empty # pages are disjoint
        seen_ids.concat(page_ids)
      end

      expect(seen_ids).to match_array(matching_rooms.map(&:id))
      expect(seen_ids).not_to include(*non_matching_rooms.map(&:id))
    end
  end

  describe "Task 5 UI: filter form, results frame, admin toggles" do
    let(:building) { create(:building, workspace: workspace, name: "Mason Hall") }
    let!(:listed_classroom) { create(:room, building: building, workspace: workspace, facility_code: "MLB1001") }

    before do
      # Described, so it lands in a named group rather than the Other catch-all.
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
      expect(response.body).to include("#{listed_classroom.room_number} #{listed_classroom.building.display_name}")
      # Full title: a bare 4-digit room number collides with other digits on the page.
      expect(response.body).not_to include("#{other_room.room_number} #{other_room.building.display_name}")
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

    it "renders a gallery thumbnail, ADA badge, and characteristic icon chip" do
      listed_classroom.update!(ada_seat_count: 5)
      create(:media_asset, owner: listed_classroom, workspace: workspace)
      # "projector" survives CodeNormalizer unchanged; "seating_fixed" would not.
      create(:room_characteristic, room: listed_classroom, workspace: workspace,
             short_code: "projector", description: "Media: Projector")
      create(:characteristic_display_rule, workspace: workspace, short_code: "projector", icon_key: "computer_desktop")
      sign_in(membership_with("viewer"))

      get find_a_room_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("rooms.row.ada", count: 5))
      # Element-shaped: "Buildings" can appear in building names.
      expect(response.body).not_to match(%r{>\s*Buildings\s*<})
    end

    # A <summary> may hold no focusable descendant (axe nested-interactive); needs over CARD_TAG_LIMIT chips.
    it "renders a labeled card chip and no focusable element in the summary" do
      # 5 chips: a strip of 4 plus a one-item remainder disclosure.
      create(:room_characteristic, room: listed_classroom, workspace: workspace,
             short_code: "projdigit", description: "Projection: Digital Data&Video")
      %w[lecturecap doccam whtbrd].each do |code|
        create(:room_characteristic, room: listed_classroom, workspace: workspace,
               short_code: code, description: "Media: #{code}")
      end
      sign_in(membership_with("viewer"))

      get find_a_room_path

      page = Capybara.string(response.body)
      card = page.all("li").find { |li| li.has_text?("Projector") }
      expect(card).to be_present
      summary = card.find("details summary")
      expect(summary).to have_no_css("[tabindex]")
      expect(summary).to have_no_css("[role='tooltip']")
    end
  end
end

RSpec.describe "GET /rooms/:id", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-show-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
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

    it "renders an image seating chart's alt without the PDF suffix" do
      # The factory authors an alt; clear it to reach the derived fallback.
      room.update!(seating_chart_alt: nil)
      room.seating_chart.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "seating.png",
        content_type: "image/png"
      )

      get room_path(room)

      expect(response.body).to include(I18n.t("media.derived_alt.seating_chart", room: room.display_name))
      expect(response.body).not_to include("(PDF)")
    end

    # Browsers can't decode HEIC uploads, so every display path serves a webp variant.
    it "serves the panorama viewer texture as a variant, never the original blob" do
      room.panorama.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/equirect.png")),
        filename: "pano.png",
        content_type: "image/png"
      )

      get room_path(room)

      expect(response.body).not_to include(rails_blob_path(room.panorama))
      expect(response.body).to include(
        %(data-panorama-url-value="#{rails_representation_path(room.panorama.variant(:texture))}")
      )
    end

    it "serves the seating-chart lightbox image as a variant, never the original blob" do
      room.seating_chart.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "seating.png",
        content_type: "image/png"
      )

      get room_path(room)

      expect(response.body).not_to include(rails_blob_path(room.seating_chart))
      expect(response.body).to include(rails_representation_path(room.seating_chart.variant(:lightbox)))
    end

    it "still links a PDF seating chart to its original blob" do
      room.seating_chart.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/seating_chart.pdf")),
        filename: "seating.pdf",
        content_type: "application/pdf"
      )

      get room_path(room)

      expect(response.body).to include(%(href="#{rails_blob_path(room.seating_chart, disposition: :inline)}"))
    end

    it "serves the photo frame at :full, never the original blob" do
      asset = create(:media_asset, owner: room, workspace: workspace)

      get room_path(room)

      expect(response.body).to include(rails_representation_path(asset.image.variant(:full)))
      expect(response.body).not_to include(rails_blob_path(asset.image))
    end

    # Pinned on its own so the 44x32 swatch can't widen to :full.
    it "renders the chip swatch at :card" do
      room.panorama.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/equirect.png")),
        filename: "pano.png",
        content_type: "image/png"
      )
      asset = create(:media_asset, owner: room, workspace: workspace)

      get room_path(room)

      expect(response.body).to include(rails_representation_path(asset.image.variant(:card)))
    end

    # Needs two or more assets: one can't trip the N+1.
    it "serves the JSON gallery for multiple assets without an attachment N+1" do
      create(:media_asset, owner: room, workspace: workspace, position: 1)
      create(:media_asset, owner: room, workspace: workspace, position: 2)

      get room_path(room), as: :json

      json = response.parsed_body
      expect(json["media"]["gallery_urls"].length).to eq(2)
      expect(json["media"]["gallery_urls"]).to all(include("/rails/active_storage/representations/"))
    end

    it "renders the building breadcrumb crumb as a link when the building is not hidden" do
      get room_path(room)

      expect(response.body).to include(%(href="#{building_path(building)}"))
    end

    it "renders the building breadcrumb crumb as plain text when the building is hidden" do
      hidden_building = create(:building, :hidden, workspace: workspace)
      room_in_hidden_building = create(:room, building: hidden_building, workspace: workspace, facility_code: "MLB1002")

      get room_path(room_in_hidden_building)

      expect(response.body).not_to include(%(href="#{building_path(hidden_building)}"))
      expect(response.body).to include(hidden_building.display_name)
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

    it "renders the building breadcrumb crumb as a link to the admin building page" do
      get room_path(room)

      expect(response.body).to include(%(href="#{building_path(building)}"))
    end
  end

  describe "conditional GET (D14)" do
    let(:viewer) { membership_with("viewer") }

    before do
      sign_in(viewer)
      # Drains sign-in's flash first: Rails' EtagWithFlash folds flash into the ETag.
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

      create(:media_asset, owner: room, workspace: workspace)

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when a media attachment (seating chart) is added" do
      get room_path(room), as: :json
      etag = response.headers["ETag"]

      room.seating_chart.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "room.png",
        content_type: "image/png"
      )

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when a seating-chart attachment is replaced" do
      room.seating_chart.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "room.png",
        content_type: "image/png"
      )

      get room_path(room), as: :json
      etag = response.headers["ETag"]

      # Replacing attaches a new row, so its created_at moves the max.
      room.seating_chart.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "room-replacement.png",
        content_type: "image/png"
      )

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "busts the ETag when a seating-chart attachment is removed" do
      room.seating_chart.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "room.png",
        content_type: "image/png"
      )

      get room_path(room), as: :json
      etag = response.headers["ETag"]

      # purge, not purge_later: the row must be gone before the next request.
      room.seating_chart.purge

      get room_path(room), headers: { "If-None-Match" => etag }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "produces a different ETag for an admin than a viewer of the same room" do
      get room_path(room), as: :json
      viewer_etag = response.headers["ETag"]

      Membership.find_by!(user: viewer, workspace: workspace).update!(role: Role.system_default!("admin"))
      # Re-signing in leaves a fresh flash; drain it before comparing ETags.
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
        %w[thumbnail_url panorama_url seating_chart_url gallery_urls]
      )
      expect(json["contacts"]).to be_present
      expect(json["url"]).to eq(room_url(full_room))
    end
  end
end

RSpec.describe "GET /rooms/:id/floor_plan", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-floor-plan-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let(:building) { create(:building, workspace: workspace) }
  let(:floor) { create(:floor, building: building, workspace: workspace, label: "2") }
  let!(:room) { create(:room, building: building, workspace: workspace, floor: floor, facility_code: "MLB1001") }

  describe "as a signed-in viewer" do
    let(:viewer) { membership_with("viewer") }

    before { sign_in(viewer) }

    it "returns 200 for a room with a floor" do
      get room_floor_plan_path(room)

      expect(response).to have_http_status(:ok)
    end

    it "redirects to the room with the no_floor notice when the room has no floor" do
      floorless_room = create(:room, building: building, workspace: workspace, floor: nil, facility_code: "MLB1099")

      get room_floor_plan_path(floorless_room)

      expect(response).to redirect_to(room_path(floorless_room))
      expect(flash[:notice]).to eq(I18n.t("rooms.floor_plan.no_floor"))
    end

    it "redirects a hidden room to Find a Room instead of rendering" do
      hidden_room = create(:room, :hidden, building: building, workspace: workspace, floor: floor, facility_code: "MLB1098")

      get room_floor_plan_path(hidden_room)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:notice]).to eq(I18n.t("rooms.inactive_notice"))
    end

    it "renders a PDF floor plan as a link instead of an image" do
      floor.plan.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/seating_chart.pdf")),
        filename: "floor-2.pdf",
        content_type: "application/pdf"
      )

      get room_floor_plan_path(room)

      expect(response.body).to include(
        I18n.t("rooms.floor_plan.plan_pdf_link", building: building.display_name, floor: floor.label)
      )
      expect(response.body).to include(%(href="#{rails_blob_path(floor.plan, disposition: :inline)}"))
      expect(response.body).not_to include("<img")
    end

    it "serves an image floor plan as a variant, never the original blob" do
      floor.plan.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "floor-2.png",
        content_type: "image/png"
      )

      get room_floor_plan_path(room)

      expect(response.body).not_to include(rails_blob_path(floor.plan))
      expect(response.body).to include(rails_representation_path(floor.plan.variant(:display)))
    end

    # "B100" CASTs to 0 and sorts before numeric labels; "20" < "100" numerically.
    it "lists same-floor classrooms in natural room-number order" do
      lettered = create(:room, building: building, workspace: workspace, floor: floor,
                         room_number: "B100", facility_code: "MLB2001")
      low = create(:room, building: building, workspace: workspace, floor: floor,
                     room_number: "20", facility_code: "MLB2002")
      high = create(:room, building: building, workspace: workspace, floor: floor,
                      room_number: "100", facility_code: "MLB2003")

      get room_floor_plan_path(room)

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

      get room_floor_plan_path(hidden_room)

      expect(response).to have_http_status(:ok)
    end
  end
end

RSpec.describe "GET /rooms/:id/edit", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-edit-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
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

    # The declared variant, not inline transformations: the warm job processes it by name.
    it "renders each persisted gallery photo via the declared :gallery variant" do
      asset = create(:media_asset, owner: room, workspace: workspace)
      sign_in(admin)

      get edit_room_path(room)

      expect(response.body).to include(rails_representation_path(asset.image.variant(:gallery)))
    end

    it "offers HEIC/HEIF in the image pickers' accept lists" do
      sign_in(admin)

      get edit_room_path(room)

      expect(response.body).to include(
        %(accept="image/png,image/jpeg,image/webp,image/heic,image/heif")
      )
    end
  end
end

RSpec.describe "PATCH /rooms/:id", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-update-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
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

    it "updates the curated field via Curation::Apply and writes exactly one audited ActivityLog" do
      expect {
        patch room_path(room), params: { room: { nickname: "New Name" } }
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room))
      expect(room.reload.nickname).to eq("New Name")

      log = ActivityLog.last
      expect(log.action).to eq("room.updated")
      expect(log.before_after).to eq(
        "before" => { "nickname" => "Old Name" }, "after" => { "nickname" => "New Name" }
      )
    end

    it "writes no ActivityLog when an admin resubmits the same nickname unchanged" do
      expect {
        patch room_path(room), params: { room: { nickname: room.nickname } }
      }.not_to change(ActivityLog, :count)

      expect(room.reload.nickname).to eq("Old Name")
    end

    it "re-renders :edit with 422 on a panorama validation failure and writes no ActivityLog" do
      expect {
        patch room_panorama_path(room), params: {
          room: { panorama: fixture_file_upload("seating_chart.pdf", "application/pdf") }
        }
      }.not_to change(ActivityLog, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(room.reload.panorama).not_to be_attached
    end

    it "takes only the room's own fields: media sent to the room update is ignored" do
      expect {
        patch room_path(room), params: {
          room: { nickname: "New Name", panorama: fixture_file_upload("room.jpg", "image/jpeg") }
        }
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(room_path(room))
      expect(room.reload.nickname).to eq("New Name")
      expect(room.panorama).not_to be_attached
      expect(ActivityLog.last.action).to eq("room.updated")
    end

    it "adds a photo from an empty add-photo row, in the room's workspace" do
      create(:media_asset, owner: room, workspace: workspace, position: 1)

      expect {
        patch room_gallery_path(room), params: { room: { gallery_attributes: {
          "1" => { position: "2", image: fixture_file_upload("room.jpg", "image/jpeg") }
        } } }
      }.to change { room.gallery.count }.from(1).to(2)

      expect(response).to have_http_status(:redirect)
      expect(room.gallery.last.workspace).to eq(room.workspace)
    end

    it "persists a gallery reorder" do
      first = create(:media_asset, owner: room, workspace: workspace, position: 1)
      second = create(:media_asset, owner: room, workspace: workspace, position: 2)

      patch room_gallery_path(room), params: {
        room: { gallery_attributes: {
          "0" => { id: first.id, position: "2" },
          "1" => { id: second.id, position: "1" }
        } }
      }

      expect(response).to redirect_to(edit_room_path(room))
      expect(flash[:notice]).to eq(I18n.t("rooms.edit.gallery_saved"))
      expect(first.reload.position).to eq(2)
      expect(second.reload.position).to eq(1)
    end

    it "422s and mutates nothing when gallery_attributes references another room's gallery image id" do
      other_building = create(:building, workspace: workspace)
      other_room = create(:room, building: other_building, workspace: workspace)
      foreign_image = create(:media_asset, owner: other_room, workspace: workspace, position: 3)

      expect {
        patch room_gallery_path(room), params: {
          room: { gallery_attributes: { "0" => { id: foreign_image.id, position: "1" } } }
        }
      }.not_to raise_error

      expect(response).to have_http_status(:unprocessable_entity)
      expect(page.find("dialog#gallery-editor", visible: :all).text(:all)).to include(I18n.t("rooms.edit.stale_gallery"))
      expect(room.gallery.reload).to be_empty
      expect(foreign_image.reload.position).to eq(3)
      expect(foreign_image.owner).to eq(other_room)
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
