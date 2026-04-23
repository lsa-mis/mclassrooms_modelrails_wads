require "rails_helper"

RSpec.describe "Footer: Manage cookies reopens Biscuit banner", type: :system do
  it "renders a Manage cookies button in the footer on public pages" do
    visit root_path
    within("footer") do
      expect(page).to have_button(I18n.t("footer.manage_cookies"))
    end
  end

  it "reopens the Biscuit banner when clicked" do
    visit root_path

    # Simulate a post-consent state: hide the banner and show the manage-link
    # (exactly what the Biscuit controller does after acceptAll/rejectAll).
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) { banner.hidden = true; banner.setAttribute("aria-hidden", "true"); }
      const link = document.querySelector('[data-biscuit-target="manageLink"]');
      if (link) link.hidden = false;
    JS

    # Sanity: banner should now be hidden
    expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :hidden)

    within("footer") do
      click_button I18n.t("footer.manage_cookies")
    end

    # Biscuit's reopen action calls #showBanner, making the banner visible again.
    expect(page).to have_css("[data-biscuit-target='banner']:not([hidden])", wait: 2)
  end

  it "hides the gem's floating .biscuit-manage-link so only our footer button shows" do
    visit root_path
    # The gem still renders it in the DOM; our CSS hides it with display:none !important.
    expect(page).to have_css(".biscuit-manage-link", visible: :hidden)
    expect(page).not_to have_css(".biscuit-manage-link", visible: true)
  end
end
