require "rails_helper"

# Regression coverage for the shared header rendering inside a Rails engine
# (markdowndocs). The header renders `avatar_for`, which calls
# `image_tag variant` — and `image_tag` resolves the variant into a URL
# through the *current* rendering context's URL helpers. From inside the
# markdowndocs engine, the engine's routes don't include Active Storage
# routes, so the resolution fails with:
#
#   Can't resolve image into URL:
#   undefined method 'to_model' for an instance of ActiveStorage::VariantWithRecord
#
# The fix is to anchor the resolution through `main_app.url_for(variant)`
# in both `avatar_helper#render_upload_avatar` and
# `workspace_helper#render_workspace_logo`.
RSpec.describe "Header rendering inside engines (avatar URL resolution)", type: :request do
  let(:user) { create(:user) }

  context "authenticated user with an uploaded avatar visiting a markdowndocs engine page" do
    before do
      user.avatar.attach(fixture_file_upload("avatar.png", "image/png"))
      user.update!(avatar_source: "upload")
      sign_in(user)
    end

    it "renders /docs without raising 'Can't resolve image into URL'" do
      # Without main_app.url_for(variant), this raises ActionView::Template::Error
      # during avatar_for inside _user_menu_avatar_button.html.erb. With the fix,
      # the page renders 200 OK and the avatar image tag uses an Active Storage
      # rails_blob_path URL.
      #
      # Using Nokogiri to assert on the img element rather than a regex on the
      # raw response body — keeps source-code scanners (accesslint et al.) from
      # mis-reading a regex pattern as a real img tag without an alt attribute.
      get "/docs/developer/getting-started"

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      avatar_img = doc.at_css("#user_avatar_header img")
      expect(avatar_img).not_to be_nil, "avatar img tag should render inside #user_avatar_header"
      expect(avatar_img["src"]).to match(%r{/rails/active_storage/(blobs|representations)/})
    end
  end

  context "authenticated user whose workspace has a logo, visiting a markdowndocs engine page" do
    let(:workspace) { create(:workspace) }
    let(:role) do
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true }
      end
    end

    before do
      create(:membership, user: user, workspace: workspace, role: role)
      workspace.logo.attach(fixture_file_upload("avatar.png", "image/png"))
      sign_in(user)
    end

    it "does not raise when the workspace switcher or any workspace_icon_for call is reached from an engine context" do
      # The workspace switcher / sidebar renders workspace_icon_for, which
      # uses image_tag variant in render_workspace_logo. Same engine-URL
      # bug as avatar_helper; same fix (main_app.url_for).
      get "/docs/developer/getting-started"
      expect(response).to have_http_status(:ok)
    end
  end
end
