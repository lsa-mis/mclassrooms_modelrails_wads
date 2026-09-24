# frozen_string_literal: true

require "tailwind_merge"

# Base class for modelrails_ui components.
#
# The `cn` class-merge helper is backed by `tailwind_merge` (a small pure-Ruby
# runtime dependency) so a per-instance `class:` passthrough correctly OVERRIDES
# conflicting base utilities — e.g. `class: "rounded-full"` beats a base
# `rounded-md`, instead of both being emitted and CSS source-order deciding the
# winner. The install generator adds `gem "tailwind_merge"` to your Gemfile.
class ApplicationComponent < ViewComponent::Base
  private

  # Merge Tailwind class lists into one string, dropping nils/blanks and letting
  # later (passthrough) utilities win conflicts via tailwind_merge.
  #
  # tailwind_merge 1.x builds its internal LruRedux::Cache (NOT the thread-safe
  # variant), so a single shared Merger is not concurrency-safe under Puma.
  # We keep one Merger per thread: each thread owns its cache, so there is no
  # shared mutable state and no lock on this hot path.
  def cn(*classes)
    joined = classes.flatten.compact.reject { |c| c.to_s.empty? }.join(" ")
    (Thread.current[:modelrails_ui_tw_merge] ||= TailwindMerge::Merger.new).merge(joined)
  end

  # Merge a caller's `**html_attrs` over a component's own attributes, with `data:`
  # merged ONE LEVEL DEEPER than everything else.
  #
  # A flat merge is silently destructive in both directions. A component whose
  # wrapper sets `data: { controller: "floating", action: … }` loses all of it the
  # moment a caller passes any `data:` of their own — no error, no warning, the
  # component simply stops working. Fixed for popover's `trigger_attrs:` in #204;
  # this is the same bug one merge site over, and test_wrapper_data_merge.rb keeps
  # it fixed everywhere.
  #
  # Precedence is deliberately split: a caller still wins on ordinary attributes
  # (that is the existing passthrough contract), but the component's own `data:`
  # wins inside the merged hash, because those keys are its wiring rather than
  # styling and a caller overwriting them breaks the component silently.
  #
  # Keys are normalised to SYMBOLS on both sides first, because `content_tag`
  # de-duplicates neither `:key` against `"key"` nor the reverse — it emits both and
  # lets the browser choose. Either type would fix that; symbols are the one that
  # keeps `wrapper_attrs` overridable, since `sheet` and `drawer` call `super` and
  # then reach into `base[:data]`.
  def merge_html_attrs(own, caller_attrs)
    own_attrs = own.to_h { |key, value| [ key.to_sym, value ] }
    passthrough = caller_attrs.to_h { |key, value| [ key.to_sym, value ] }
    own_data = (own_attrs.delete(:data) || {}).to_h { |key, value| [ key.to_sym, value ] }
    caller_data = (passthrough.delete(:data) || {}).to_h { |key, value| [ key.to_sym, value ] }

    merged = own_attrs.merge(passthrough)
    data = caller_data.merge(own_data)
    data.empty? ? merged : merged.merge(data: data)
  end
end
