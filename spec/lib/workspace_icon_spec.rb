require "rails_helper"

# #654: the workspace-icon fallback chain — logo → owner's uploaded avatar
# (personal workspaces only) → initials — is a directly-testable unit that
# answers with UI::AvatarComponent args; helpers only render its answer.
RSpec.describe WorkspaceIcon do
  def args_for(workspace, size: :md)
    described_class.new(workspace, size: size).avatar_args do |variant|
      "variant:#{variant.variation.transformations[:resize_to_fill].join('x')}"
    end
  end

  # logo_source accompanies the attachment, as Identity#apply's write path
  # guarantees (it sets "upload" on attach and purges on source change).
  def attach_logo(workspace)
    workspace.logo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "logo.png",
      content_type: "image/png"
    )
    workspace.update_columns(logo_source: "upload")
  end

  def attach_avatar(user)
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    user.update_columns(avatar_source: "upload")
  end

  it "renders the logo with recovery fallback when one is attached" do
    workspace = create(:workspace, name: "Acme Co")
    attach_logo(workspace)

    args = args_for(workspace, size: :md)

    expect(args[:src]).to eq("variant:40x40")
    expect(args[:fallback]).to eq(workspace.identity.initials)
    expect(args[:size]).to eq(:md)
  end

  it "falls back to the owner's uploaded avatar for a personal workspace without a logo" do
    user = create(:user, first_name: "Pat", last_name: "Quill")
    attach_avatar(user)
    workspace = user.personal_workspace

    args = args_for(workspace, size: :sm)

    expect(args[:src]).to eq("variant:32x32")
    expect(args[:fallback]).to eq(user.identity.initials)
  end

  it "does not use the owner's gravatar — the owner fallback is uploads only" do
    user = create(:user, :with_gravatar)
    user.update_columns(avatar_source: "gravatar")
    workspace = user.personal_workspace

    args = args_for(workspace)

    expect(args[:src]).to be_nil
    expect(args[:fallback]).to eq(workspace.identity.initials)
  end

  it "renders initials for an inconsistent row (attachment present, non-upload source)" do
    workspace = create(:workspace, name: "Acme Co")
    attach_logo(workspace)
    workspace.update_columns(logo_source: "initials")

    args = args_for(workspace)

    expect(args[:src]).to be_nil
    expect(args[:fallback]).to eq(workspace.identity.initials)
  end

  it "renders workspace initials for an org workspace without a logo" do
    workspace = create(:workspace, name: "Acme Co")

    args = args_for(workspace)

    expect(args[:src]).to be_nil
    expect(args[:fallback]).to eq(workspace.identity.initials)
  end

  it "carries nil hue at the default color and the custom hue otherwise (#755)" do
    workspace = create(:workspace, name: "Acme Co")
    expect(args_for(workspace)[:hue]).to be_nil

    workspace.update_columns(primary_color: 270)
    expect(args_for(workspace)[:hue]).to eq(270)
  end
end
