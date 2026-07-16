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

    it "orders distinctive tags first, then filterable alpha, then the rest, with common codes demoted last" do
      # projdigit (Projector) is CARD_TAG index 0 but COMMON (~97% of rooms), so
      # it is demoted past the distinctive whtbrd and the other chips.
      expect(helper.room_card_chips(room).map(&:short_code))
        .to eq(%w[whtbrd zzz_early aaa_late zzz_feat projdigit])
    end

    it "demotes a near-universal code below the distinctive chips so cards differentiate" do
      order = helper.room_card_chips(room).map(&:short_code)
      expect(order.index("projdigit")).to be > order.index("whtbrd")
      expect(order.last).to eq("projdigit")
    end

    it "emphasizes an actively-filtered code first, even when it is common" do
      # Filtering ON Projector means the user asked for it — it leads the card.
      order = helper.room_card_chips(room, active_codes: Set["projdigit"]).map(&:short_code)
      expect(order.first).to eq("projdigit")
    end
  end

  describe "#active_card_codes" do
    it "expands merged filter tokens to their member vendor codes" do
      allow(helper).to receive(:params)
        .and_return(ActionController::Parameters.new(characteristics: %w[movableseating whtbrd]))
      expect(helper.active_card_codes).to eq(Set["movetablet", "tablesmov", "whtbrd"])
    end
  end
end
