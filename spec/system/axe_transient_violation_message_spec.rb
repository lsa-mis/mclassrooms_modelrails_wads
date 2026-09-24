require "rails_helper"

# Self-test for the failure MESSAGE, not for the audit (#1189).
#
# Every a11y call site is a pair: `expect(axe_clean_in_both_themes?).to be(true),
# axe_violations_in_both_themes.join("\n")`. The message is a positional argument,
# so Ruby evaluates it eagerly on every run — and before this fix it ran its own
# pair of audits. A violation present during the check and gone by the message
# produced a failure with an EMPTY message: no rule, no selector, no theme.
#
# Deterministically empty rather than occasionally, because the memo is keyed on
# a DOM fingerprint: a transient is by definition a page that changed, so the
# message's audits always missed the memo and re-audited a now-clean page.
RSpec.describe "Axe transient violation message", type: :system do
  # Planting stops when the block ends, so the unconditional teardown audit
  # (axe_accessibility.rb's after-hook) sees the real, clean page and does not
  # fail the example on our own fixture.
  def planting(id, only_first: false)
    calls = 0
    active = true
    allow(self).to receive(:run_axe_audit).and_wrap_original do |original, *args, **kwargs|
      results = original.call(*args, **kwargs)
      calls += 1
      next results unless active
      next results if only_first && calls > 1

      results.merge(
        "violations" => [ {
          "id" => id,
          "help" => "planted for the message self-test",
          "impact" => "serious",
          "nodes" => []
        } ]
      )
    end
    yield
  ensure
    active = false
  end

  it "names the rule the check actually saw, even when it has already cleared" do
    visit root_path

    # only_first: the violation exists for the check and is gone by the message.
    planting("probe-transient", only_first: true) do
      expect {
        expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /probe-transient/)
    end
  end

  it "still reports a violation that is stable across audits" do
    visit root_path

    planting("probe-stable") do
      expect {
        expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError, /probe-stable/)
    end
  end

  # The message must not buy its accuracy with extra audits on green runs, which
  # is what the memo existed to prevent in the first place (#855).
  it "adds no audits to a green run" do
    visit root_path
    ensure_light_mode
    baseline = axe_audit_run_count

    expect(axe_clean_in_both_themes?).to be(true), axe_violations_in_both_themes.join("\n")

    expect(axe_audit_run_count).to eq(baseline + 2),
      "a paired assertion should cost exactly two audits — one per theme"
  end
end
