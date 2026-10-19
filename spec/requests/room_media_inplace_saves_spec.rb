require "rails_helper"

RSpec.describe "Saving a room media dialog in place", type: :request do
  let(:workspace) { create(:workspace, slug: "room-media-inplace-spec", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let(:building) { create(:building, workspace: workspace) }
  let!(:room) { create(:room, building: building, workspace: workspace, facility_code: "MAS1401") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  before { sign_in(membership_with("admin")) }

  it "closes the panorama dialog, refreshes the media in place and says it saved" do
    attach_panorama!(room)

    patch room_panorama_path(room), params: { room: { panorama_alt: "Tiered lecture hall" } }, headers: turbo

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(room.reload.panorama_alt).to eq("Tiered lecture hall")
    expect(stream_shape).to eq([
      [ "replace", "room_media_strip", "morph" ],
      [ "update", "room_media_view", nil ],
      [ "replace", "room_documents", "morph" ],
      [ "append", "toast-pills", nil ]
    ])
    strip = Nokogiri::HTML5.fragment(streams.first.at_css("template").inner_html)
    expect(strip.at_css("[data-controller~='modal']:has(dialog#panorama-editor)")["data-modal-open-value"]).not_to eq("true")
    expect(streams.last.inner_html).to include(I18n.t("rooms.edit.panorama_saved"))
  end

  it "renders the seating chart dialog closed in the refreshed documents card" do
    patch room_seating_chart_path(room), params: { room: { seating_chart: fixture_file_upload("seating_chart.pdf", "application/pdf") } },
                           headers: turbo

    expect(room.reload.seating_chart).to be_attached
    documents = streams.find { it["target"] == "room_documents" }
    expect(documents.inner_html).to include('id="seating-chart-editor"')
    expect(streams.last.inner_html).to include(I18n.t("rooms.edit.seating_chart_saved"))
  end

  it "closes the photos dialog and rebuilds it with what was saved" do
    photo = create(:media_asset, owner: room, workspace: workspace, position: 1)

    patch room_gallery_path(room), params: { room: { gallery_attributes: {
      "0" => { id: photo.id, image_alt: "Front row from the lectern" }
    } } }, headers: turbo

    expect(photo.reload.image_alt).to eq("Front row from the lectern")
    strip = streams.find { it["target"] == "room_media_strip" }
    expect(strip.inner_html).to include("Front row from the lectern")
    expect(strip.inner_html).to include(I18n.t("rooms.edit.manage_photos", count: 1))
    expect(streams.last.inner_html).to include(I18n.t("rooms.edit.gallery_saved"))
  end

  it "returns to the edit page, not view mode, when the save isn't a Turbo request" do
    attach_panorama!(room)

    patch room_panorama_path(room), params: { room: { panorama_alt: "Tiered lecture hall" } }

    expect(response).to redirect_to(edit_room_path(room))
    expect(flash[:notice]).to eq(I18n.t("rooms.edit.panorama_saved"))
  end

  it "still returns to view mode after saving the room's own fields" do
    patch room_path(room), params: { room: { nickname: "The Big One" } }, headers: turbo

    expect(response).to redirect_to(room_path(room))
    expect(flash[:notice]).to eq(I18n.t("rooms.edit.success"))
  end

  it "keeps a rejected media save on the edit page with its error" do
    patch room_panorama_path(room), params: { room: { panorama: fixture_file_upload("seating_chart.pdf", "application/pdf") } },
                           headers: turbo

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.media_type).to eq("text/html")
    expect(page).to have_css("[data-modal-open-value='true'] dialog#panorama-editor", visible: :all)
  end
end
