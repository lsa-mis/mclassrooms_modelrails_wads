# frozen_string_literal: true

# Runtime CSP-violation capture for system specs (#128): fails any example
# whose page fired `securitypolicyviolation` — the bug class #499/#500 proved
# source-level scans are blind to. Mechanics: one init script per browser
# process accumulates violations in sessionStorage so same-tab navigations
# within an example don't lose them; the after-hook reads AND clears, so
# nothing bleeds across examples. See /docs/developer/testing.
module CspViolationCapture
  LISTENER_JS = <<~JS
    document.addEventListener("securitypolicyviolation", (e) => {
      try {
        const list = JSON.parse(sessionStorage.getItem("__cspViolations") || "[]");
        list.push(
          `${e.violatedDirective} blocked ${e.blockedURI || "inline"} on ${e.documentURI}` +
          (e.sourceFile ? ` (${e.sourceFile}:${e.lineNumber})` : "")
        );
        sessionStorage.setItem("__cspViolations", JSON.stringify(list));
      } catch (_) {}
    });
  JS

  # Violations that are expected and documented. Substring match; every entry
  # needs a reason. (Empty today — the enforced-in-test policy plus the
  # session-nonce generator should produce zero violations anywhere.)
  ALLOWED_VIOLATIONS = [].freeze

  def install_csp_violation_listener
    browser = page.driver.browser
    return if browser.instance_variable_get(:@__csp_listener_installed)

    cdp_add_init_script(LISTENER_JS)
    browser.instance_variable_set(:@__csp_listener_installed, true)
  end

  def captured_csp_violations
    raw = page.evaluate_script(<<~JS)
      (() => {
        try {
          const v = sessionStorage.getItem("__cspViolations");
          sessionStorage.removeItem("__cspViolations");
          return v;
        } catch (_) { return null; }
      })()
    JS
    JSON.parse(raw || "[]")
  rescue StandardError
    # Page not in a queryable state (mid-navigation, closed window) — the
    # example's own expectations still gate it.
    []
  end
end

RSpec.configure do |config|
  config.include CspViolationCapture, type: :system

  config.before(:each, type: :system) do
    install_csp_violation_listener
  end

  config.after(:each, type: :system) do
    violations = captured_csp_violations.reject do |violation|
      CspViolationCapture::ALLOWED_VIOLATIONS.any? { |allowed| violation.include?(allowed) }
    end

    expect(violations).to be_empty, <<~MSG
      The browser reported Content-Security-Policy violations during this
      example — something the page needed was silently blocked (the #499
      bug class: the feature dies, the suite stays green):
        #{violations.uniq.join("\n  ")}
      Fix the policy or the offending markup; add to ALLOWED_VIOLATIONS in
      spec/support/csp_violation_capture.rb only with a written reason.
    MSG
  end
end
