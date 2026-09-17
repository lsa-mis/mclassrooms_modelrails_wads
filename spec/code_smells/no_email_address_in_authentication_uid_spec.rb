# frozen_string_literal: true

require "rails_helper"

# An email-provider authentication's uid is the user's id (#903). It used to be
# a second copy of users.email_address, kept in step by three writers — and the
# third, `authentications.email.update_all(uid: …)`, skipped the uid uniqueness
# validator on its way past. One fact in two columns, and under deterministic
# encryption the two columns held identical bytes for the same address, so a
# leaked dump joined them.
#
# `Authentication#assign_email_uid` is now the only writer, and it fills blanks
# only. Anything that hands the column an address puts the mirror back — in the
# app, in a seed, or in a fixture that then teaches the next author the old
# shape. This is the issue's own grep, standing, plus the spellings the grep
# never had: the factory's `uid { … }` block and the validation-skipping
# `update_column(s)`.
RSpec.describe "Code smell: nothing writes an address into authentications.uid" do
  # `update_all` and `update_column(s)` both skip validations, so they are named
  # as writers in their own right rather than as an accident of the argument.
  def patterns
    {
      /\buid:\s*\S*email_address/ => "uid: … email_address",
      /\buid\s*=\s*\S*email_address/ => "uid = … email_address",
      /\buid\s*\{\s*\S*email_address/ => "uid { … email_address }",
      /update_all\(\s*uid:/ => "update_all(uid:)",
      /update_columns?\(\s*:?uid\b.*email_address/ => "update_column(:uid, … email_address)"
    }
  end

  # "path" => why this file legitimately writes the address into uid. Everything
  # under db/ is scanned (a future data migration must not restore the mirror
  # unnoticed), so the two files that must are named here instead of a glob
  # quietly excusing the whole directory.
  def allowed_writers
    {
      "db/migrate/20260907120000_rewrite_email_authentication_uids_to_user_ids.rb" =>
        "#903's data migration: `down` restores the mirror on purpose, because " \
        "it is the way back to the release whose writers assume uid IS the address",
      "spec/migrations/rewrite_email_authentication_uids_to_user_ids_spec.rb" =>
        "manufactures the pre-#903 row (update_column) so `up` has something " \
        "to rewrite, and asserts `down` puts the address back"
    }.freeze
  end

  def scanned_files
    (Dir[Rails.root.join("app/**/*.{rb,erb}")] +
      Dir[Rails.root.join("lib/**/*.rb")] +
      Dir[Rails.root.join("db/**/*.rb")] +
      Dir[Rails.root.join("spec/**/*.rb")]).sort - [ __FILE__ ]
  end

  def writes_in(file)
    File.readlines(file).each_with_index.filter_map do |line, i|
      label = patterns.find { |pattern, _| line.match?(pattern) }&.last
      "#{i + 1}: #{label} — #{line.strip}" if label
    end
  end

  it "writes no address into an email authentication's uid, anywhere" do
    offenders = scanned_files.flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      next [] if allowed_writers.key?(relative)

      writes_in(file).map { |write| "#{relative}:#{write}" }
    end

    expect(offenders).to be_empty, <<~MSG
      An email authentication's uid is the user's id (#903), assigned by
      Authentication#assign_email_uid. These put the address back:

      #{offenders.join("\n")}

      Create the row without a uid and let the model fill it. A file that must
      write the address — only #903's own migration and its spec do — belongs
      in allowed_writers in this spec, with its reason.
    MSG
  end

  it "carries no stale exemptions" do
    stale = allowed_writers.keys.reject do |relative|
      path = Rails.root.join(relative)
      path.exist? && writes_in(path).any?
    end

    expect(stale).to be_empty,
      "These exemptions name a file that no longer writes an address into uid " \
      "— it moved, went away, or stopped needing the exemption — so the " \
      "allow-list is describing code that isn't there and would silently " \
      "excuse a future file that reuses the path:\n  #{stale.join("\n  ")}"
  end
end
