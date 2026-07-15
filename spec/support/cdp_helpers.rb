# Ferrum/CDP helpers — the pure-Ruby replacements for the Playwright-specific
# operations the system specs used via `page.driver.with_playwright_page`.
# Cuprite exposes the underlying Ferrum::Browser at `page.driver.browser`.
#
# Playwright → ferrum cheatsheet:
#   pw.evaluate(async IIFE returning X)  -> cdp_evaluate_async(js)   (js resolves via arguments[last])
#   pw.evaluate(sync JS, no return)      -> cdp_execute(js)
#   pw.evaluate(sync JS returning X)     -> cdp_evaluate(js)
#   pw.context.add_init_script(src)      -> cdp_add_init_script(src)  (call BEFORE visiting)
#   pw.keyboard.press(key)               -> cdp_press(key)
#   pw.mouse.click(x, y)                 -> cdp_click_at(x, y)
#   pw.context.clear_cookies             -> cdp_clear_cookies
#   pw_page.set_viewport_size(w, h)      -> cdp_resize(w, h)
#   pw_page.emulate_media(reducedMotion: "reduce") -> cdp_emulate_reduced_motion
#   pw.context.new_cdp_session(...).send_message(m, params:) -> cdp_command(m, **params)
#   pw_page.route(pattern, handler)      -> see "Network interception" below (no 1:1 wrapper;
#                                            ferrum's callback API differs enough to inline per-spec)
module CdpHelpers
  def cdp_browser
    page.driver.browser
  end

  # Inject/run JS as a statement (no implicit `return`). Ferrum's `evaluate`
  # wraps the source in `function(){ return X }`, which breaks UMD bundles like
  # axe-core that self-assign to `window`; `execute` runs the raw statement.
  def cdp_execute(js)
    cdp_browser.execute(js)
  end

  # Evaluate JS and return its value (synchronous).
  def cdp_evaluate(js)
    cdp_browser.evaluate(js)
  end

  # Await an async expression. The JS must resolve by calling the LAST argument:
  # `...then(v => arguments[arguments.length - 1](v))`. Returns the resolved value.
  def cdp_evaluate_async(js, wait: 20)
    cdp_browser.evaluate_async(js, wait)
  end

  # Register a script that runs before page scripts on every SUBSEQUENT
  # navigation (Playwright's add_init_script). Call BEFORE `visit`.
  def cdp_add_init_script(source)
    cdp_command("Page.addScriptToEvaluateOnNewDocument", source: source)
  end

  # DOM key names ferrum's keyboard doesn't recognize as-is — it only knows
  # its own short aliases (:down/:up/:left/:right) for the arrow keys.
  ARROW_KEY_ALIASES = { "ArrowDown" => :Down, "ArrowUp" => :Up, "ArrowLeft" => :Left, "ArrowRight" => :Right }.freeze

  # Press a single key ("Enter", "Tab", "Escape", "Space", "ArrowDown", " ", "a")
  # or a Playwright-style "+"-joined combo ("Control+Shift+KeyA", "Shift+F10").
  # Modifier tokens (Control/Shift/Alt/Meta/Command) precede the final token;
  # a trailing "Key<X>" token (Playwright's physical-key naming) resolves to
  # the bare letter so the dispatched event's `key` matches what JS listeners
  # read (`event.key.toLowerCase() === "a"`, not `event.code`).
  def cdp_press(key)
    tokens = key.to_s.split("+")
    final = resolve_key_token(tokens.pop)
    modifiers = tokens.map { |t| t.downcase.to_sym }
    cdp_browser.keyboard.type(modifiers.empty? ? final : modifiers + [ final ])
  end

  # Click at absolute viewport coordinates.
  def cdp_click_at(x, y)
    cdp_browser.mouse.click(x: x, y: y)
  end

  # Clear all cookies for the current browsing context.
  def cdp_clear_cookies
    cdp_browser.cookies.clear
  end

  # Send a raw CDP command to the current page (WebAuthn domain, etc.).
  def cdp_command(method, **params)
    cdp_browser.page.command(method, **params)
  end

  # Resize the viewport (Playwright's set_viewport_size).
  def cdp_resize(width, height)
    cdp_browser.page.resize(width: width, height: height)
  end

  # Force prefers-reduced-motion: reduce for the current page.
  def cdp_emulate_reduced_motion
    cdp_command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
  end

  # Network interception (Playwright's page.route(pattern, handler)). Ferrum
  # uses a global `browser.on(:request)` callback + `browser.network.intercept`
  # rather than a per-route handler, so this is a THIN WRAPPER, not 1:1:
  # matches by substring/regex against the request URL and yields the matched
  # Ferrum::Network::InterceptedRequest to the block, which MUST call
  # `.continue`, `.abort`, or `.respond(**opts)` on it. Non-matching requests
  # are auto-continued — every request must get one of those three calls or
  # ferrum leaves it hanging indefinitely.
  #
  #   cdp_intercept(%r{/settings/avatar}) do |request|
  #     patch_count += 1 if request.method == "PATCH"
  #     sleep 1 if request.method == "PATCH" # example: delay to widen a race window
  #     request.continue
  #   end
  def cdp_intercept(pattern)
    cdp_browser.network.intercept
    cdp_browser.on(:request) do |request|
      matched = pattern.is_a?(Regexp) ? request.match?(pattern) : request.url.include?(pattern)
      matched ? yield(request) : request.continue
    end
  end

  private

  # Resolve one "+"-split token from cdp_press into what ferrum's
  # Keyboard#type expects: named keys (Symbol, via ferrum's own alias table)
  # or literal characters (String — ferrum's Symbol lookup is a hard #fetch
  # that KeyErrors on anything outside its curated alias list, e.g. :a or
  # :arrowdown, so single characters must stay Strings).
  def resolve_key_token(token)
    return :Space if token == " "

    letter = token[/\AKey([A-Za-z])\z/, 1]
    return letter.downcase if letter

    ARROW_KEY_ALIASES.fetch(token) { token.length == 1 ? token : token.to_sym }
  end
end

RSpec.configure do |config|
  config.include CdpHelpers, type: :system
end
