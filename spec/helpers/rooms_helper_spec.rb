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
      add_characteristic("aaa_feat", "Aaa")          # filterable, non-priority
      add_characteristic("bbb_feat", "Bbb")          # filterable, non-priority
      add_characteristic("zzz_feat", "Zzz")          # NOT filterable
      allow(helper).to receive(:filterable_codes)
        .and_return(Set["projdigit", "whtbrd", "aaa_feat", "bbb_feat"])
    end

    it "returns RoomPresenter::Chip objects" do
      expect(helper.room_card_chips(room)).to all(be_a(RoomPresenter::Chip))
    end

    it "orders CARD_TAG_CODES first (fixed priority), then filterable alpha, then the rest alpha" do
      expect(helper.room_card_chips(room).map(&:short_code))
        .to eq(%w[projdigit whtbrd aaa_feat bbb_feat zzz_feat])
    end
  end
end
