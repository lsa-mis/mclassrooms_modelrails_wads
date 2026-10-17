require "rails_helper"

RSpec.describe "Room media editing dialogs", type: :request do
  let(:workspace) { create(:workspace, slug: "room-media-dialogs-spec", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let(:building) { create(:building, workspace: workspace) }
  let!(:room) { create(:room, building: building, workspace: workspace, facility_code: "MAS1401") }
  let(:admin) { membership_with("admin") }

  before { sign_in(admin) }

  def dialog(id) = page.find("dialog##{id}", visible: :all)

  describe "the panorama dialog" do
    before do
      attach_panorama!(room)
      get edit_room_path(room)
    end

    it "is full width with a large preview and no auto-alt toggle" do
      expect(page).to have_css("dialog#panorama-editor [data-testid='media-preview'] img", visible: :all)
      expect(dialog("panorama-editor").all("input[name*='derived_ok']", visible: :all)).to be_empty
      expect(dialog("panorama-editor")).to have_css("textarea[name='room[panorama_alt]']", visible: :all)
    end

    it "offers Upload new and a Remove that submits its own form" do
      editor = dialog("panorama-editor")
      expect(editor).to have_css("label[for='room_panorama']", text: I18n.t("rooms.edit.upload_new_panorama"), visible: :all)
      remove = editor.find("button[form='panorama-remove-form']", visible: :all)
      expect(remove.text(:all)).to include(I18n.t("rooms.edit.remove_panorama"))
      expect(remove["data-turbo-confirm"]).to be_present

      remove_form = page.find("form#panorama-remove-form", visible: :all)
      expect(page.all("form#panorama-editor-form form", visible: :all)).to be_empty
      expect(remove_form["action"]).to eq(room_panorama_path(room))
      expect(remove_form).to have_css("input[name='_method'][value='delete']", visible: :all)
    end

    it "keeps the preview image decorative" do
      expect(dialog("panorama-editor").find("[data-testid='media-preview'] img", visible: :all)["alt"]).to eq("")
    end

    it "docks the stage under the media strip by its own classes, not the page's test hooks" do
      stage = page.find("#room_panorama_stage", visible: :all)
      expect(stage["class"].split).to include("rounded-b-md")
      expect(stage["class"].split).not_to include("rounded-md")
      expect(page.find("[data-testid='media-stage']", visible: :all)["class"].split).not_to include("mt-6")
      expect(page.find("[data-testid='media-dock']", visible: :all)["class"]).not_to include("data-testid")

      get room_path(room)
      expect(page.find("#room_panorama_stage", visible: :all)["class"].split).to include("rounded-md")
      expect(page.find("[data-testid='media-stage']", visible: :all)["class"].split).to include("mt-6")
    end

    it "keeps the stage out of Turbo's permanent elements in edit mode only" do
      expect(page).to have_css("#room_panorama_stage", visible: :all)
      expect(page).to have_no_css("#room_panorama_stage[data-turbo-permanent]", visible: :all)

      get room_path(room)
      expect(page).to have_css("#room_panorama_stage[data-turbo-permanent]", visible: :all)
    end
  end

  describe "the photos dialog" do
    let!(:first_photo) { create(:media_asset, owner: room, workspace: workspace, position: 1) }
    let!(:second_photo) { create(:media_asset, owner: room, workspace: workspace, position: 2) }

    it "is a full-size dialog, not a side sheet, with a large image and no toggle per photo" do
      get edit_room_path(room)

      photos = dialog("gallery-editor")
      expect(photos["class"].to_s + photos.find(:xpath, "./*", visible: :all)["class"].to_s).to include("max-w-4xl")
      expect(photos.all("[data-testid='media-preview'] img", visible: :all).size).to eq(2)
      expect(photos.all("input[name*='derived_ok']", visible: :all)).to be_empty
      expect(page.all("form#gallery-editor-form input[name*='_destroy']", visible: :all)).to be_empty
    end

    it "gives each photo Upload new and a Remove backed by its own form" do
      get edit_room_path(room)

      photos = dialog("gallery-editor")
      remove = photos.find("button[form='photo-remove-#{second_photo.id}']", visible: :all)
      expect(remove.text(:all)).to include(I18n.t("rooms.edit.remove_photo"))
      expect(remove["data-turbo-confirm"]).to be_present

      remove_form = page.find("form#photo-remove-#{second_photo.id}", visible: :all)
      expect(remove_form["action"]).to eq(room_photo_path(room, second_photo))
      expect(remove_form).to have_css("input[name='_method'][value='delete']", visible: :all)
      expect(photos).to have_css("input[type='file'][name$='[image]']", visible: :all, minimum: 2)
    end

    it "removes one photo and reopens the photos dialog, which says what was removed" do
      expect { delete room_photo_path(room, second_photo) }.to change { room.gallery.count }.from(2).to(1)

      expect(response).to redirect_to(edit_room_path(room, open: "gallery"))
      follow_redirect!
      photos = page.find("[data-modal-open-value='true'] dialog#gallery-editor", visible: :all)
      description = page.find("##{photos['aria-describedby']}", visible: :all)
      expect(description.text(:all)).to eq(I18n.t("rooms.edit.photo_removed", position: 2))
    end

    it "re-renders a rejected photo replacement with its error instead of failing" do
      patch room_gallery_path(room), params: { room: { gallery_attributes: {
        "0" => { id: first_photo.id, image: fixture_file_upload("seating_chart.pdf", "application/pdf") }
      } } }

      expect(response).to have_http_status(:unprocessable_entity)
      photos = page.find("[data-modal-open-value='true'] dialog#gallery-editor", visible: :all)
      expect(photos.all("[data-testid='media-preview'] img", visible: :all).size).to eq(2)
      expect(first_photo.reload.image.blob.content_type).not_to eq("application/pdf")
    end

    it "replaces an existing photo's file" do
      original_blob = first_photo.image.blob

      patch room_gallery_path(room), params: { room: { gallery_attributes: {
        "0" => { id: first_photo.id, image: fixture_file_upload("room.jpg", "image/jpeg") }
      } } }

      expect(first_photo.reload.image.blob).not_to eq(original_blob)
    end
  end

  it "starts every upload control's accessible name with the words its label shows" do
    attach_panorama!(room)
    room.seating_chart.attach(io: file_fixture("seating_chart.pdf").open, filename: "chart.pdf",
                              content_type: "application/pdf")
    create(:media_asset, owner: room, workspace: workspace, position: 1)

    get edit_room_path(room)

    uploads = page.all("dialog input[type='file'][aria-label]", visible: :all)
    expect(uploads.map { it["aria-label"] }).to contain_exactly(
      I18n.t("rooms.edit.upload_new_panorama"), I18n.t("rooms.edit.upload_new_seating_chart"),
      "#{I18n.t("rooms.edit.upload_new_photo")} 1"
    )
    uploads.each do |input|
      shown = page.all("label[for='#{input[:id]}']", visible: :all).reject { it["data-testid"] == "media-preview" }.sole
      expect(input["aria-label"]).to start_with(shown.text(:all).squish)
    end
  end

  it "no longer accepts the auto-alt flag" do
    attach_panorama!(room)
    patch room_panorama_path(room), params: { room: { panorama_derived_ok: "1", panorama_alt: "A lecture hall" } }

    expect(room.reload.panorama_derived_ok).to be(false)
    expect(room.panorama_alt).to eq("A lecture hall")
  end

  it "drops the auto-alt toggle from the building photo form" do
    get edit_building_path(building)

    expect(page.all("input[name='building[photo_derived_ok]']", visible: :all)).to be_empty
  end
end
