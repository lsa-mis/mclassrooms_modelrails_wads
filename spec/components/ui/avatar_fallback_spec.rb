# frozen_string_literal: true

require "rails_helper"

# A 404 on the image src leaves a broken-image glyph — the one case `fallback:` did not
# cover, because it only stood in for a NIL src. Recovering needs an `error` handler, and
# CSP forbids inline `onerror`, so a controller swaps in the initials.
#
# The wrapper is only rendered when BOTH a src and a fallback are given: with a src alone
# there is nothing to fall back to, so those call sites keep their bare <img>.
RSpec.describe "UI::AvatarComponent image error fallback", type: :component do
  def avatar(**opts) = render_inline(UI::AvatarComponent.new(**opts))

  it "renders a bare img when there is no fallback to swap in" do
    avatar(src: "/a.png", aria_label: "Dave")

    expect(page).to have_css("img[src='/a.png']")
    expect(page).to have_no_css("[data-controller~=avatar]")
  end

  it "renders initials directly when there is no src" do
    avatar(fallback: "DC", aria_label: "Dave")

    expect(page).to have_css("span", text: "DC")
    expect(page).to have_no_css("img")
  end

  it "wires the error handler when both a src and a fallback exist" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave")

    expect(page).to have_css("[data-controller~=avatar] img[data-action~='error->avatar#showFallback']")
  end

  it "ships the initials alongside, hidden until the image fails" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave")

    fallback = page.find("[data-avatar-target=fallback]", visible: :all)
    expect(fallback.text(:all)).to eq("DC")
    expect(fallback[:hidden]).to be_truthy
  end

  # The img is named while it loads; the standby initials are named for after it fails.
  # Only one of the two is ever exposed, because `hidden` keeps the other out.
  it "names the avatar once among visible nodes" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave")

    expect(page).to have_css("[aria-label='Dave']", count: 1)
  end

  # A caller `data:` used to splat over the wiring and silently disable the fallback —
  # the component would render, look right, and never recover from a 404.
  it "keeps the error wiring when the caller passes their own data" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave", data: { testid: "user-avatar" })

    img = page.find("img", visible: :all)
    expect(img["data-action"]).to include("error->avatar#showFallback")
    expect(img["data-avatar-target"]).to eq("image")
    expect(img["data-testid"]).to eq("user-avatar")
  end

  # The <img> carries the accessible name and is REMOVED on failure, so the initials must
  # carry it afterwards. Hardcoding aria-hidden left the avatar absent from the
  # accessibility tree entirely once the image 404'd.
  it "names the standby initials so the avatar survives in the accessibility tree" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave")

    fallback = page.find("[data-avatar-target=fallback]", visible: :all)
    expect(fallback["aria-label"]).to eq("Dave")
    expect(fallback["role"]).to eq("img")
  end

  # While hidden it must not double up the name; the hidden attribute does that for us.
  it "exposes exactly one named avatar while the image is still loading" do
    avatar(src: "/a.png", fallback: "DC", aria_label: "Dave")

    expect(page).to have_css("[aria-label='Dave']", count: 1)
  end
end
