module PageHelpers
  def focused_text
    page.evaluate_script("document.activeElement.textContent.trim()")
  end

  def dismiss_cookie_banner
    page.execute_script(<<~JS)
      document.querySelectorAll('[data-controller="biscuit"]').forEach(el => el.remove());
    JS
  end
end

RSpec.configure do |config|
  config.include PageHelpers, type: :system
end
