require "rails_helper"

RSpec.describe RoomPresenter do
  let(:building) do
    create(:building, name: "Mason Hall", address: "419 S State St", city: "Ann Arbor", state: "MI", zip: "48109")
  end
  let(:room) do
    create(:room, building: building, facility_code: "MLB1200", nickname: "Aud 3",
                  instructional_seat_count: 40, ada_seat_count: nil)
  end

  describe "#capacity_line" do
    it "interpolates the instructional and ADA seat counts" do
      room.update!(ada_seat_count: 5)
      expect(described_class.new(room).capacity_line).to eq(I18n.t("rooms.show.capacity", students: 40, ada: 5))
    end

    it "coerces a nil ADA seat count to 0" do
      expect(room.ada_seat_count).to be_nil
      expect(described_class.new(room).capacity_line).to eq(I18n.t("rooms.show.capacity", students: 40, ada: 0))
    end
  end

  describe "#chips" do
    it "sorts chips by short_code regardless of creation order" do
      create(:room_characteristic, room: room, code: "c1", short_code: "zzz")
      create(:room_characteristic, room: room, code: "c2", short_code: "mmm")
      create(:room_characteristic, room: room, code: "c3", short_code: "aaa")

      expect(described_class.new(room).chips.map(&:short_code)).to eq(%w[aaa mmm zzz])
    end

    it "builds a chip's label/description from the characteristic's own attributes" do
      create(:room_characteristic, room: room, code: "c1", short_code: "whiteboard",
                                    description: "Whiteboard", long_description: "Wall-mounted dry-erase board")

      chip = described_class.new(room).chips.first
      expect(chip.label).to eq("Whiteboard")
      expect(chip.description).to eq("Wall-mounted dry-erase board")
    end

    it "falls back to FALLBACK_ICON when the characteristic has no matching display rule at all" do
      create(:room_characteristic, room: room, code: "c1", short_code: "norule")

      chip = described_class.new(room).chips.first
      expect(chip.icon_name).to eq(RoomPresenter::FALLBACK_ICON)
      expect(chip.team_learning).to be false
    end

    it "falls back to FALLBACK_ICON when the rule's icon_key is blank" do
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "blankicon", icon_key: nil)
      create(:room_characteristic, room: room, code: "c1", short_code: "blankicon")

      chip = described_class.new(room).chips.first
      expect(chip.icon_name).to eq(RoomPresenter::FALLBACK_ICON)
    end

    it "falls back to FALLBACK_ICON when the rule's icon_key isn't a registered icon" do
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "badicon", icon_key: "not_a_real_icon")
      create(:room_characteristic, room: room, code: "c1", short_code: "badicon")

      chip = described_class.new(room).chips.first
      expect(chip.icon_name).to eq(RoomPresenter::FALLBACK_ICON)
    end

    it "uses the rule's icon_key when it names a real registered icon" do
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "network", icon_key: "globe_alt")
      create(:room_characteristic, room: room, code: "c1", short_code: "network")

      chip = described_class.new(room).chips.first
      expect(chip.icon_name).to eq(:globe_alt)
    end
  end

  describe "FALLBACK_ICON" do
    # The plan's reference implementation names `:sparkles` as the fallback
    # icon; this checkout's icon catalog (app/assets/icons/{outline,solid})
    # does not ship a sparkles.svg, so `RoomPresenter` substitutes a
    # confirmed-registered icon instead (see the ADAPTATION comment above
    # `FALLBACK_ICON` in app/lib/room_presenter.rb). Asserting against the
    # constant itself — not a hardcoded `:sparkles` literal — means this
    # guard keeps working if the constant's value ever changes again.
    it "is a real, registered icon so a fallback chip can never raise IconRegistry::NotFound downstream" do
      expect(IconRegistry.exists?(RoomPresenter::FALLBACK_ICON)).to be true
    end
  end

  # Taxonomy phase 2 (2026-07-12 sprint): the room page buckets on the SAME
  # question-group vocabulary the Find-a-Room panel uses — category_override
  # holds the display-ready group name ("Seats & layout", …). One data lever,
  # one mental model across both pages.
  describe "feature grouping" do
    it "lands a rule-less characteristic in #other_features" do
      create(:room_characteristic, room: room, code: "c1", short_code: "mystery")

      expect(described_class.new(room).other_features.map(&:short_code)).to eq(%w[mystery])
    end

    it "lands an override OUTSIDE the question-group vocabulary in #other_features instead of dropping it" do
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "mystery", category_override: "Recording")
      create(:room_characteristic, room: room, code: "c1", short_code: "mystery")

      expect(described_class.new(room).other_features.map(&:short_code)).to eq(%w[mystery])
    end

    it "groups chips by CharacteristicDisplayRule#category_override, data-driven across all four question groups" do
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "whiteboard", category_override: "Write on")
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "projector", category_override: "Show & present")
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "capture", category_override: "Recorded & accessible")
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "tablet", category_override: "Seats & layout")
      %w[whiteboard projector capture tablet].each_with_index do |code, i|
        create(:room_characteristic, room: room, code: "c#{i}", short_code: code)
      end

      presenter = described_class.new(room)
      expect(presenter.write_on.map(&:short_code)).to eq(%w[whiteboard])
      expect(presenter.show_present.map(&:short_code)).to eq(%w[projector])
      expect(presenter.recorded_accessible.map(&:short_code)).to eq(%w[capture])
      expect(presenter.seats_layout.map(&:short_code)).to eq(%w[tablet])
    end

    it "picks team_learning rules into #team_based_learning across categories, without removing them from their own category" do
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "clicker",
                                            category_override: "Show & present", team_learning: true)
      create(:characteristic_display_rule, workspace: room.workspace, short_code: "podtable",
                                            category_override: "Seats & layout", team_learning: true)
      create(:room_characteristic, room: room, code: "c1", short_code: "clicker")
      create(:room_characteristic, room: room, code: "c2", short_code: "podtable")

      presenter = described_class.new(room)
      expect(presenter.team_based_learning.map(&:short_code)).to contain_exactly("clicker", "podtable")
      expect(presenter.show_present.map(&:short_code)).to include("clicker")
      expect(presenter.seats_layout.map(&:short_code)).to include("podtable")
    end
  end

  describe "#share_text" do
    it "joins display name, full address, capacity line, and URL with an em dash separator" do
      presenter = described_class.new(room, url: "https://example.edu/rooms/1")

      expect(presenter.share_text.split(" — ")).to eq(
        [ room.display_name, building.full_address, presenter.capacity_line, "https://example.edu/rooms/1" ]
      )
    end

    it "omits a nil URL rather than leaving a trailing separator" do
      presenter = described_class.new(room, url: nil)

      expect(presenter.share_text.split(" — ")).to eq(
        [ room.display_name, building.full_address, presenter.capacity_line ]
      )
    end
  end

  describe "#as_json" do
    # rails_blob_url/rails_representation_url need a host — this isn't a
    # request spec, so Rails.application.routes.default_url_options has none
    # configured by default (only config.action_mailer.default_url_options
    # is set in config/environments/test.rb). Setting it here keeps URL
    # generation deterministic instead of raising ActionController::UrlGenerationError.
    around do |example|
      original = Rails.application.routes.default_url_options.dup
      Rails.application.routes.default_url_options[:host] = "test.host"
      example.run
      Rails.application.routes.default_url_options.replace(original)
    end

    context "a minimal room (no floor, unit, contact, or attachments)" do
      it "produces the room-show JSON shape with nil department/contacts and no media URLs" do
        json = described_class.new(room, url: "https://example.edu/rooms/1").as_json

        expect(json).to include(
          id: room.id,
          rmrecnbr: room.rmrecnbr,
          facility_code: room.facility_code,
          display_name: room.display_name,
          nickname: room.nickname,
          floor_label: nil,
          room_number: room.room_number,
          room_type: room.room_type,
          square_feet: room.square_feet,
          instructional_seat_count: room.instructional_seat_count,
          ada_seat_count: room.ada_seat_count,
          department: nil,
          contacts: nil,
          characteristics: [],
          url: "https://example.edu/rooms/1"
        )
        expect(json[:building]).to eq(id: building.id, name: building.name, abbreviation: building.abbreviation)
        expect(json[:media]).to eq(
          photo_url: nil, thumbnail_url: nil, panorama_url: nil, seating_chart_url: nil, gallery_urls: []
        )
      end
    end

    context "a fully populated room" do
      let(:floor) { create(:floor, building: building, label: "2") }
      let(:unit) { create(:unit, workspace: room.workspace, department_group: "ENGIN", description: "Engineering raw descr") }

      before do
        # UnitDisplayName override so `department[:description]` (Unit#display_name)
        # is provably distinct from the raw `description` column mapped to
        # `group_description` — proves the presenter maps the right field to
        # each JSON key rather than accidentally aliasing the same value twice.
        create(:unit_display_name, workspace: room.workspace, department_group: "ENGIN", display_name: "College of Engineering")
        room.update!(floor: floor, unit: unit)
        create(:room_characteristic, room: room, code: "c1", short_code: "wifi")
        create(:room_contact, room: room)
        create(:room_gallery_image, room: room, position: 0)
        room.photo.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "photo.png", content_type: "image/png"
        )
      end

      it "populates floor_label, department, characteristics, contacts, and media URLs" do
        json = described_class.new(room).as_json

        expect(json[:floor_label]).to eq("2")
        expect(json[:department]).to eq(
          id: unit.id, description: "College of Engineering", group: "ENGIN", group_description: "Engineering raw descr"
        )
        expect(json[:characteristics]).to eq([ "wifi" ])

        expect(json[:contacts]).to eq(
          scheduling_name: "Scheduling Office",
          scheduling_email: "scheduling@example.edu",
          scheduling_phone: "734-555-0100",
          scheduling_detail_url: "https://example.edu/rooms/schedule",
          scheduling_usage_guidelines_url: "https://example.edu/rooms/guidelines",
          support_department_id: "1000",
          support_department_description: "Facilities Support",
          support_email: "support@example.edu",
          support_phone: "734-555-0199",
          support_url: "https://example.edu/support"
        )

        expect(json[:media][:photo_url]).to be_present
        expect(json[:media][:thumbnail_url]).to be_present
        expect(json[:media][:thumbnail_url]).not_to eq(json[:media][:photo_url])
        expect(json[:media][:gallery_urls].size).to eq(1)
        expect(json[:media][:panorama_url]).to be_nil
        expect(json[:media][:seating_chart_url]).to be_nil
      end
    end
  end
end
