# frozen_string_literal: true

# Stimulus boot lags behind page load, so an event dispatched before a
# controller connects is silently dropped — under random spec ordering an
# interactive preview spec can be the first to hit a cold module cache, an
# intermittent failure (#525 was exactly the gate not yet covering
# /draft_harness). This waits once, centrally, after any visit to a gated
# path; window.Stimulus is exposed in
# app/javascript/controllers/application.js. See /docs/developer/testing.
module StimulusReady
  GATED_PATHS = [ "/rails/view_components/", "/draft_harness" ].freeze

  def visit(path, *args, **kwargs)
    super.tap do
      wait_for_stimulus_controllers if GATED_PATHS.any? { |gated| path.to_s.include?(gated) }
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
