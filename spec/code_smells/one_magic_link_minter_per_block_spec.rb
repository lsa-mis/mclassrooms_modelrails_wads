require "rails_helper"

# `MagicLinkToken.create_for_email` supersedes every prior unconsumed token for
# an address — a partial unique index enforces one live token per email — so a
# spec that drives the app into minting (submitting the lookup form) and then
# mints its own is two writers competing for one slot. Whichever lands second
# wins, and when that is the app's, the token the test is about to click is
# already dead: the callback rejects it, and because the session has begun the
# redirect lands on root_path carrying "invalid or has expired".
#
# That is #846, and #796 three days before it. #796 answered with `wait: 10`;
# a timeout cannot fix a data race, it only bets on which writer finishes
# first, and the run that finally reproduced it already had a raised global
# wait in effect. Removing the second writer is what fixes it.
#
# Two shapes are legitimate and stay allowed:
#   * minting WITHOUT driving the form — the single writer is the test
#     (expired/consumed/unknown-token cases), and
#   * driving the form WITHOUT minting — the single writer is the app, and
#     the test reads the token back out of the delivered mail, exactly as a
#     real recipient does.
# Only the two together are the bug, so the scan is per-block rather than
# per-file: one file may legitimately do each in different examples.
RSpec.describe "One party mints the magic-link token per example" do
  # Clicking the lookup form's continue button routes to SessionsController#lookup,
  # which mints via deliver_magic_link for existing users AND registrations alike.
  def server_mint_pattern = /sessions\.new\.continue/

  def test_mint_pattern = /MagicLinkToken\.create_for_email/

  # Spec files are conventional enough that example/hook/method openers are a
  # reliable block boundary; a false boundary can only SPLIT a block, which
  # makes the scan miss a violation, never invent one.
  def block_start_pattern = /^\s*(it|specify|scenario|before|after|def)\b/

  def blocks_in(source)
    source.each_line.with_index(1).slice_before { |line, _| line.match?(block_start_pattern) }
  end

  def violations_in(path)
    blocks_in(File.read(path)).filter_map do |block|
      next unless block.any? { |line, _| line.match?(server_mint_pattern) }

      offending = block.find { |line, _| line.match?(test_mint_pattern) }
      next unless offending

      "#{path}:#{offending.last}"
    end
  end

  it "never drives the app into minting and then mints again in the same block" do
    offenders = Dir[Rails.root.join("spec/system/**/*.rb")].sort.flat_map { |path| violations_in(path) }

    expect(offenders).to be_empty, <<~MSG
      These blocks submit the lookup form (the app mints) and then mint a second
      token themselves, racing two writers for one slot:

      #{offenders.join("\n")}

      Fix by removing one writer. For sign-in SETUP use `sign_in_via_form(user)`.
      Where the lookup form is the subject, keep it and read the token out of the
      delivered mail with `magic_link_token_from_email` instead of minting.
    MSG
  end
end
