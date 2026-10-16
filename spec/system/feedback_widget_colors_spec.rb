require "rails_helper"

RSpec.describe "Feedback widget colors", type: :system do
  def hovered_and_expected_background(selector)
    page.execute_script("document.querySelector(#{selector.to_json}).style.transition = 'none'")
    find(selector).hover
    page.evaluate_script(<<~JS)
      (() => {
        const probe = document.createElement("div");
        probe.style.backgroundColor = "var(--color-interactive-hover)";
        document.body.append(probe);
        const expected = getComputedStyle(probe).backgroundColor;
        probe.remove();
        return [getComputedStyle(document.querySelector(#{selector.to_json})).backgroundColor, expected];
      })()
    JS
  end

  %w[light dark].each do |theme|
    it "hovers the trigger and the submit button to the interactive hover color in the #{theme} theme" do
      visit page_path(:contact)
      click_button I18n.t("biscuit.banner.accept_all")
      expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :hidden)
      set_theme(theme)

      trigger, expected = hovered_and_expected_background("#lsa-tdx-feedback-trigger")
      expect(trigger).to eq(expected)

      click_button I18n.t("pages.contact.feedback.cta")
      expect(page).to have_css("#lsa-tdx-feedback-modal", visible: true)

      submit, expected = hovered_and_expected_background(".lsa-tdx-feedback-submit-btn")
      expect(submit).to eq(expected)
    end
  end
end
