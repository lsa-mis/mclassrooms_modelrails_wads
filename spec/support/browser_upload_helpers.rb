# frozen_string_literal: true

# Helper for browser file uploads in Cuprite system specs.
#
# Cuprite selects a file by handing Chrome a *path-backed* File via CDP
# (`DOM.setFileInputFiles`). Under this harness, handing `attach_file` a path
# that points straight into `spec/fixtures/files/` leaves Chrome unable to read
# the bytes it was given: at upload time (a multipart form submit, or an Active
# Storage direct-upload read) the browser throws `NotReadableError`, so the
# request never leaves Chrome and Ferrum times out waiting for a navigation /
# response that never comes. (The old Playwright driver tolerated the fixture
# path; Cuprite does not — and a plain Cuprite session outside this harness
# reads the same file fine, so it is specific to driving uploads from the
# fixtures dir here.)
#
# Uploading a private, per-example copy under `tmp/` reads reliably. The copy
# keeps the fixture's original basename, because some flows (e.g. the bulk-upload
# filename matcher) key off the uploaded filename. Copies are removed after each
# system example.
module BrowserUploadHelpers
  # Returns the path (String) to a fresh, private copy of `fixture_name` (a name
  # under `spec/fixtures/files`), suitable to pass to `attach_file`. The copy
  # keeps `fixture_name`'s basename.
  def browser_upload_fixture(fixture_name)
    source = file_fixture(fixture_name)
    dir = Rails.root.join("tmp", "browser-uploads", SecureRandom.hex(8))
    FileUtils.mkdir_p(dir)
    dest = dir.join(File.basename(fixture_name.to_s))
    FileUtils.cp(source, dest)
    (@browser_upload_dirs ||= []) << dir
    dest.to_s
  end
end

RSpec.configure do |config|
  config.include BrowserUploadHelpers, type: :system

  config.after(:each, type: :system) do
    Array(@browser_upload_dirs).each { |dir| FileUtils.remove_entry(dir) if File.exist?(dir) }
  end
end
