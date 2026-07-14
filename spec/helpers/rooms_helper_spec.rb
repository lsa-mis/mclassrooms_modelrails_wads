require "rails_helper"

RSpec.describe RoomsHelper, type: :helper do
  describe "#room_card_chips" do
    let(:workspace) { create(:workspace, personal: false) }
    let(:building)  { create(:building, workspace: workspace) }
    let(:room)      { create(:room, building: building, workspace: workspace) }

    # `Feature: <label>` so RoomPresenter#chip_label parses to `<label>`.
    def add_characteristic(code, label)
      create(:room_characteristic, room: room, workspace: workspace,
             short_code: code, description: "Feature: #{label}")
      create(:characteristic_display_rule, workspace: workspace, short_code: code)
    end

    before do
      add_characteristic("whtbrd", "Whiteboard")     # CARD_TAG_CODES index 3
      add_characteristic("projdigit", "Projector")   # CARD_TAG_CODES index 0
      # Labels deliberately contradict short_code order (label "Aaa" < "Bbb",
      # but short_code "aaa_late" < "zzz_early") so the "alpha by LABEL" rule
      # is actually load-bearing: sorting by short_code instead would flip
      # this pair and fail the ordering expectation below.
      add_characteristic("zzz_early", "Aaa")         # filterable, non-priority
      add_characteristic("aaa_late", "Bbb")          # filterable, non-priority
      add_characteristic("zzz_feat", "Zzz")          # NOT filterable
      allow(helper).to receive(:filterable_codes)
        .and_return(Set["projdigit", "whtbrd", "zzz_early", "aaa_late"])
    end

    it "returns RoomPresenter::Chip objects" do
      expect(helper.room_card_chips(room)).to all(be_a(RoomPresenter::Chip))
    end

    it "orders CARD_TAG_CODES first (fixed priority), then filterable alpha by label, then the rest alpha" do
      expect(helper.room_card_chips(room).map(&:short_code))
        .to eq(%w[projdigit whtbrd zzz_early aaa_late zzz_feat])
    end
  end
end
