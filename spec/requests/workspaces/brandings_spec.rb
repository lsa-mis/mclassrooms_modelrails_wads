require "rails_helper"

RSpec.describe "Workspace Brandings", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/branding/edit to sign in" do
      get edit_workspace_branding_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before { sign_in(user) }

    describe "GET /workspaces/:workspace_slug/branding/edit" do
      it "renders the branding form" do
        get edit_workspace_branding_path(workspace)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding" do
      it "updates the primary color" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "#6366f1" }
        }
        expect(workspace.reload.primary_color).to eq("#6366f1")
      end

      it "redirects with success message" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "#6366f1" }
        }
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding with logo and color together" do
      it "updates both logo and color" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: {
          logo: file,
          workspace: { primary_color: "#0d9488" }
        }
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.primary_color).to eq("#0d9488")
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding via upload modal" do
      it "removes the logo when remove_image is sent" do
        workspace.logo.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "logo.png", content_type: "image/png"
        )
        patch workspace_branding_path(workspace), params: { remove_image: "1" }
        expect(workspace.reload.logo).not_to be_attached
        expect(response).to redirect_to(edit_workspace_branding_path(workspace))
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding with logo + original" do
      it "saves both logo and logo_original" do
        cropped = fixture_file_upload("avatar.png", "image/png")
        original = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: {
          logo: cropped,
          logo_original: original,
          crop_coordinates: '{"x":5,"y":10,"w":80,"h":80}'
        }
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.logo_original).to be_attached
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding (turbo_stream)" do
      it "responds with turbo stream that updates logo and closes modal" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "#6366f1" }
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("workspace_logo_branding")
        expect(response.body).to include("modal-closer")
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding crop save vs hub save" do
      it "does NOT close modal when saving a crop (logo file present)" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: { logo: file },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).not_to include("modal-closer")
        expect(response.body).to include("workspace_logo_branding")
      end
    end

    describe "PATCH /workspaces/:workspace_slug/branding with crop_coordinates edge cases" do
      context "with malformed JSON" do
        it "ignores malformed JSON without crashing" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch workspace_branding_path(workspace), params: {
            logo: file,
            logo_original: file,
            crop_coordinates: "not-valid-json{"
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          expect(response.status).to be < 500
        end
      end

      context "with coords missing required keys" do
        it "ignores coords missing required keys" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch workspace_branding_path(workspace), params: {
            logo: file,
            logo_original: file,
            crop_coordinates: '{"foo":"bar"}'
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          expect(response.status).to be < 500
          workspace.reload
          expect(workspace.logo_original.blob.metadata["crop"]).to be_nil
        end
      end

      context "with non-numeric coord values" do
        it "ignores coords with non-numeric values" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch workspace_branding_path(workspace), params: {
            logo: file,
            logo_original: file,
            crop_coordinates: '{"x":"a","y":"b","w":"c","h":"d"}'
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          expect(response.status).to be < 500
          workspace.reload
          expect(workspace.logo_original.blob.metadata["crop"]).to be_nil
        end
      end

      context "with valid coords" do
        it "stores coords when they have the expected shape" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch workspace_branding_path(workspace), params: {
            logo: file,
            logo_original: file,
            crop_coordinates: '{"x":5,"y":10,"w":80,"h":80}'
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          workspace.reload
          expect(workspace.logo_original.blob.metadata["crop"]).to eq({ "x" => 5, "y" => 10, "w" => 80, "h" => 80 })
        end
      end
    end

    context "when save fails during branding update" do
      before do
        allow_any_instance_of(Workspace).to receive(:update).and_return(false)
        allow_any_instance_of(Workspace).to receive_message_chain(:errors, :full_messages).and_return([ "Primary color is invalid" ])
      end

      it "returns 422 turbo stream for turbo_stream requests (not a redirect)" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "bad-value" }
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "still renders edit with unprocessable_content for non-turbo HTML requests" do
        patch workspace_branding_path(workspace), params: {
          workspace: { primary_color: "bad-value" }
        }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when avatar_source changes to initials (logo removal)" do
      before do
        workspace.logo.attach(fixture_file_upload("avatar.png", "image/png"))
        workspace.logo_original.attach(fixture_file_upload("avatar.png", "image/png"))
      end

      it "purges logo attachments when avatar_source is set to initials" do
        patch workspace_branding_path(workspace), params: {
          avatar_source: "initials"
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.status).to be < 400
        workspace.reload
        expect(workspace.logo).not_to be_attached
        expect(workspace.logo_original).not_to be_attached
      end
    end

    context "when cropped image is sent via JS saveCrop path" do
      let(:valid_png) { fixture_file_upload("avatar.png", "image/png") }

      it "accepts 'avatar'/'avatar_original' params and attaches as logo" do
        patch workspace_branding_path(workspace), params: {
          avatar: valid_png,
          avatar_original: valid_png,
          avatar_source: "upload",
          crop_coordinates: '{"x":0,"y":0,"w":100,"h":100}'
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.status).to be < 400
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.logo_original).to be_attached
      end

      it "still accepts 'logo'/'logo_original' params for regular HTML form" do
        patch workspace_branding_path(workspace), params: {
          logo: valid_png,
          logo_original: valid_png,
          avatar_source: "upload",
          crop_coordinates: '{"x":0,"y":0,"w":100,"h":100}'
        }

        expect(response.status).to be < 400
        workspace.reload
        expect(workspace.logo).to be_attached
        expect(workspace.logo_original).to be_attached
      end
    end

    describe "logo_source persistence" do
      it "sets logo_source to upload when a logo is saved via crop" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch workspace_branding_path(workspace), params: {
          avatar: file,
          avatar_original: file,
          avatar_source: "upload",
          crop_coordinates: '{"x":0,"y":0,"w":100,"h":100}'
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        workspace.reload
        expect(workspace.logo_source).to eq("upload")
      end

      it "sets logo_source to initials when source is switched" do
        workspace.update!(logo_source: "upload")
        workspace.logo.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "logo.png",
          content_type: "image/png"
        )

        patch workspace_branding_path(workspace), params: {
          avatar_source: "initials"
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        workspace.reload
        expect(workspace.logo_source).to eq("initials")
      end

      it "rejects invalid source values" do
        patch workspace_branding_path(workspace), params: {
          avatar_source: "invalid_source"
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "authorization" do
      it "rejects non-owner/admin access" do
        viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
        viewer = create(:user)
        create(:membership, user: viewer, workspace: workspace, role: viewer_role)
        sign_in(viewer)
        get edit_workspace_branding_path(workspace)
        expect(response).to redirect_to(workspace_path(workspace))
      end
    end
  end
end
