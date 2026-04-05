require "rails_helper"

RSpec.describe AvatarHelper, type: :helper do
  let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }

  describe "#avatar_for" do
    context "with upload source" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
      end

      it "renders an image tag with Active Storage variant" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("img.rounded-full.object-cover")
      end

      it "renders correct size classes" do
        result = helper.avatar_for(user, size: :lg)
        expect(result).to have_css("img.w-16.h-16")
      end

      it "renders aria-hidden by default" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("img[aria-hidden='true']")
      end

      it "renders role=img with aria_label when provided" do
        result = helper.avatar_for(user, size: :md, aria_label: "Jane Doe")
        expect(result).to have_css("img[role='img'][aria-label='Jane Doe']")
        expect(result).not_to have_css("img[aria-hidden]")
      end
    end

    context "with gravatar source" do
      before do
        user.update_columns(avatar_source: "gravatar", has_gravatar: true)
      end

      it "renders an image tag with Gravatar URL" do
        result = helper.avatar_for(user, size: :md)
        hash = Digest::SHA256.hexdigest(user.email_address.strip.downcase)
        expect(result).to have_css("img[src*='gravatar.com/avatar/#{hash}']")
      end

      it "passes correct pixel size to Gravatar URL" do
        result = helper.avatar_for(user, size: :lg)
        expect(result).to have_css("img[src*='s=64']")
      end

      it "renders aria-hidden by default" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("img[aria-hidden='true']")
      end
    end

    context "with initials source" do
      before do
        user.update_columns(avatar_source: "initials")
      end

      it "renders a span with initials text" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("span", text: "JD")
      end

      it "renders correct Tailwind classes" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("span.rounded-full.bg-interactive.text-text-on-interactive")
      end

      it "renders correct size classes" do
        result = helper.avatar_for(user, size: :sm)
        expect(result).to have_css("span.w-8.h-8")
      end

      it "renders aria-hidden by default" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("span[aria-hidden='true']")
      end

      it "renders role=img with aria_label when provided" do
        result = helper.avatar_for(user, size: :md, aria_label: "Jane Doe")
        expect(result).to have_css("span[role='img'][aria-label='Jane Doe']")
      end
    end

    context "sizes" do
      before { user.update_columns(avatar_source: "initials") }

      it "renders xs size" do
        result = helper.avatar_for(user, size: :xs)
        expect(result).to have_css("span.w-6.h-6")
      end

      it "renders sm size" do
        result = helper.avatar_for(user, size: :sm)
        expect(result).to have_css("span.w-8.h-8")
      end

      it "renders md size" do
        result = helper.avatar_for(user, size: :md)
        expect(result).to have_css("span.w-10.h-10")
      end

      it "renders lg size" do
        result = helper.avatar_for(user, size: :lg)
        expect(result).to have_css("span.w-16.h-16")
      end

      it "renders xl size" do
        result = helper.avatar_for(user, size: :xl)
        expect(result).to have_css("span.w-32.h-32")
      end
    end
  end
end
