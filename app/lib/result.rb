# frozen_string_literal: true

# Fork-wide return value for service-shaped operations (roadmap Lib section,
# spec D7): every sync phase (and later phases 6/8 — availability, feedback)
# returns one of these instead of a bare boolean or raising. A plain Data
# value object rather than a class with mutable state: callers pattern-match
# on `#success?` and read `#errors` / `#payload` without any risk of a
# service reaching back in and mutating a Result after the fact.
Result = Data.define(:success, :errors, :payload) do
  # `**payload` — arbitrary keyword payload (e.g. counters:, warnings:) so
  # callers don't have to wrap it in an explicit hash literal.
  def self.success(**payload) = new(success: true, errors: [], payload:)

  # `*errors` accepts bare strings/symbols (`Result.failure("a", "b")`) or a
  # single array (`Result.failure(["a", "b"])`) — `.flatten` unifies both
  # into one list, `.map(&:to_s)` coerces symbols so `#errors` is always an
  # array of strings per the contract, never a mix of types.
  def self.failure(*errors, **payload) = new(success: false, errors: errors.flatten.map(&:to_s), payload:)

  def success? = success
end
