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
      expect(editor).to have_css("label[for='room_panorama']", text: I18n.t("rooms.edit.upload_new"), visible: :all)
      remove = editor.find("button[form='panorama-remove-form']", visible: :all)
      expect(remove.text(:all)).to include(I18n.t("rooms.edit.remove_panorama"))
      expect(remove["data-turbo-confirm"]).to be_present

      remove_form = page.find("form#panorama-remove-form", visible: :all)
      expect(page.all("form#panorama-editor-form form", visible: :all)).to be_empty
      expect(remove_form).to have_css("input[name='room[remove_panorama]'][value='1']", visible: :all)
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
      expect(remove_form["action"]).to eq(room_path(room, return_to: "gallery"))
      expect(remove_form).to have_css("input[value='#{second_photo.id}'][name$='[id]']", visible: :all)
      expect(remove_form).to have_css("input[value='1'][name$='[_destroy]']", visible: :all)
      expect(photos).to have_css("input[type='file'][name$='[image]']", visible: :all, minimum: 2)
    end

    it "removes one photo and returns to edit mode with the photos dialog open" do
      expect {
        patch room_path(room, return_to: "gallery"),
              params: { room: { gallery_attributes: { "0" => { id: second_photo.id, _destroy: "1" } } } }
      }.to change { room.gallery.count }.from(2).to(1)

      expect(response).to redirect_to(edit_room_path(room, open: "gallery"))
      follow_redirect!
      expect(page).to have_css("[data-modal-open-value='true'] dialog#gallery-editor", visible: :all)
    end

    it "replaces an existing photo's file" do
      original_blob = first_photo.image.blob

      patch room_path(room), params: { room: { gallery_attributes: {
        "0" => { id: first_photo.id, image: fixture_file_upload("room.jpg", "image/jpeg") }
      } } }

      expect(first_photo.reload.image.blob).not_to eq(original_blob)
    end
  end

  it "no longer accepts the auto-alt flag" do
    attach_panorama!(room)
    patch room_path(room), params: { room: { panorama_derived_ok: "1", panorama_alt: "A lecture hall" } }

    expect(room.reload.panorama_derived_ok).to be(false)
    expect(room.panorama_alt).to eq("A lecture hall")
  end

  it "drops the auto-alt toggle from the building photo form" do
    get edit_building_path(building)

    expect(page.all("input[name='building[photo_derived_ok]']", visible: :all)).to be_empty
  end
end
