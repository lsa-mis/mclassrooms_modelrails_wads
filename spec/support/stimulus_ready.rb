# frozen_string_literal: true

# Stimulus boot lags behind page load, so an assertion or event that lands
# before a controller connects reads a page the controller has not touched
# yet — silently dropped events, or an element still carrying its
# server-rendered class. Under random spec ordering any example can be the
# first to hit a cold module cache, so the failure is intermittent and
# load-dependent. window.Stimulus is exposed in
# app/javascript/controllers/application.js. See /docs/developer/testing.
#
# This gate was an allow-list of two paths, each added after a specific flake
# (#525 /draft_harness, then the preview path). That left 536 `visit` calls
# across 164 system spec files ungated, and #837 came back a third time on
# one of them. Per that issue, the barrier now runs after EVERY system-spec
# visit rather than being annotated call site by call site.
module StimulusReady
  def visit(path, *args, **kwargs)
    super.tap { wait_for_stimulus_controllers }
  end

  # Raises rather than returning false. A synchronization barrier that times
  # out silently is indistinguishable from one that succeeded, and the caller
  # below discards the return value — so before this, an exhausted wait and a
  # satisfied one looked identical (panel audit, 2026-08-26). The message names
  # the identifiers still unconnected, because with lazyLoadControllersFrom
  # "not connected" covers both "module still fetching" and "identifier will
  # never register" (a typo'd data-controller), and only the list distinguishes
  # them.
  def wait_for_stimulus_controllers(attempts: 25, interval: 0.1)
    attempts.times do
      return true if all_stimulus_controllers_connected?

      sleep interval
    end

    raise "Stimulus controllers never connected after #{(attempts * interval).round(1)}s: " \
          "#{unconnected_stimulus_identifiers.join(", ")} (page: #{page.current_path})"
  end

  private

  # Two guards exist because the gate now runs on every visit, not on two
  # hand-picked paths:
  # - a still-parsing document has not reached its controllers yet, so an
  #   empty match means "too early", not "nothing to wait for";
  # - a page with no controllers is ready even with no window.Stimulus (a
  #   redirect target, a plain error page). Without this the widened gate
  #   would spend its whole budget and then raise on them.
  def all_stimulus_controllers_connected?
    page.evaluate_script(<<~JS)
      (function () {
        if (document.readyState === 'loading') return false;
        var els = document.querySelectorAll('[data-controller]');
        if (els.length === 0) return true;
        if (!window.Stimulus) return false;
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
    # Mid-navigation or not-yet-evaluable: NOT connected, so keep waiting.
    # This used to return `true` — reporting "everything is connected" for any
    # evaluate_script hiccup, which is exactly what a contended runner
    # produces. The barrier was most likely to lie precisely when it mattered.
    false
  end

  def unconnected_stimulus_identifiers
    page.evaluate_script(<<~JS) || []
      (function () {
        if (!window.Stimulus) return ["(window.Stimulus absent)"];
        var out = [], els = document.querySelectorAll('[data-controller]');
        for (var i = 0; i < els.length; i++) {
          var ids = els[i].getAttribute('data-controller').split(/\\s+/);
          for (var j = 0; j < ids.length; j++) {
            if (ids[j] === '') continue;
            if (!window.Stimulus.getControllerForElementAndIdentifier(els[i], ids[j])) out.push(ids[j]);
          }
        }
        return out;
      })()
    JS
  rescue StandardError
    [ "(could not query the page)" ]
  end
end

RSpec.configure do |config|
  config.prepend StimulusReady, type: :system
end
