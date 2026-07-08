# frozen_string_literal: true

# Fork-wide return value for service-shaped operations (roadmap Lib section,
# spec D7): every sync phase (and later phases 6/8 — availability, feedback)
# returns one of these instead of a bare boolean or raising. A plain Data
# value object rather than a class with mutable state: callers pattern-match
# on `#success?` and read `#errors` / `#payload`.
#
# Immutability guarantee: the Data instance is frozen, AND its two collection
# members are shallow-frozen at construction — `result.errors << x` and
# `result.payload[:k] = v` raise FrozenError rather than silently mutating a
# structure another caller may still hold a reference to. This is a SHALLOW
# freeze: values nested inside `payload` (e.g. the `counters:` hash) are NOT
# recursively frozen, so a caller that hands its own counters hash into the
# payload and keeps mutating that reference will still see the in-place edits.
# Freeze deeply yourself if that matters.
Result = Data.define(:success, :errors, :payload) do
  # `**payload` — arbitrary keyword payload (e.g. counters:, warnings:) so
  # callers don't have to wrap it in an explicit hash literal. `.freeze` pins
  # the top-level hash (see the shallow-freeze note above).
  def self.success(**payload) = new(success: true, errors: [].freeze, payload: payload.freeze)

  # `*errors` accepts bare strings/symbols (`Result.failure("a", "b")`) or a
  # single array (`Result.failure(["a", "b"])`) — `.flatten` unifies both into
  # one list, `.compact` drops nils (a nil message must not become a
  # blank-string error), `.map(&:to_s)` coerces symbols so `#errors` is always
  # an array of strings per the contract, never a mix of types. `.freeze` pins
  # the resulting array.
  def self.failure(*errors, **payload)
    new(success: false, errors: errors.flatten.compact.map(&:to_s).freeze, payload: payload.freeze)
  end

  def success? = success
end
