# frozen_string_literal: true

# Component preview specs (spec/system/ui/*) visit a Lookbook preview and often
# interact with a Stimulus-driven behavior right away — open a menu, hover a
# card, press a key. The importmap module fetch + Stimulus boot lag behind the
# page load, so an event dispatched before the controller connects is silently
# dropped and the behavior never fires. Harmless while a warm spec always ran
# first, but random spec ordering can make an interactive spec the FIRST to run
# against a cold module cache — an intermittent failure (context_menu on
# Shift+F10, hover_card on open, and any of the other ~70 preview specs).
#
# Rather than sprinkle a wait across every spec, wait once, centrally: after any
# system-spec navigation to a /rails/view_components/ preview, block until every
# data-controller element on the page has its controller(s) connected. The
# elements are in the DOM the moment `visit` returns (server-rendered HTML) — it
# is only the JS connection that lags, so this waits for exactly that.
#
# Best-effort: proceeds after a short timeout so a controller that legitimately
# never connects (or a preview with none) can't hang the suite. Scoped to
# preview paths so non-component system specs are pass-through and unaffected.
# window.Stimulus is exposed in app/javascript/controllers/application.js.
module StimulusReady
  PREVIEW_PATH = "/rails/view_components/"

  def visit(path, *args, **kwargs)
    super.tap do
      wait_for_stimulus_controllers if path.to_s.include?(PREVIEW_PATH)
    end
  end

  def wait_for_stimulus_controllers(attempts: 25, interval: 0.1)
    attempts.times do
      return true if all_stimulus_controllers_connected?

      sleep interval
    end
    false
  end

  private

  def all_stimulus_controllers_connected?
    page.evaluate_script(<<~JS)
      (function () {
        if (!window.Stimulus) return false;
        var els = document.querySelectorAll('[data-controller]');
        for (var i = 0; i < els.length; i++) {
          var ids = els[i].getAttribute('data-controller').split(/\\s+/);
          for (var j = 0; j < ids.length; j++) {
            if (ids[j] === '') continue;
            if (!window.Stimulus.getControllerForElementAndIdentifier(els[i], ids[j])) return false;
          }
        }
        return true;
      })()
    JS
  rescue StandardError
    # If the page isn't in a queryable state (mid-navigation, JS not yet
    # evaluable), don't block — the spec's own expectations still gate it.
    true
  end
end

RSpec.configure do |config|
  config.prepend StimulusReady, type: :system
end
