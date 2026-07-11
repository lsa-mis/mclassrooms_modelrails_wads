# Bridge the U-M gateway credentials (Rails encrypted credentials) into the
# ENV that UmApi::Client / UmApi::TokenCache read. Deferred to
# after_initialize so the autoloadable `UmApiCredentials` constant is
# resolvable — referencing app/ constants during initializer load can race
# Zeitwerk (see config/initializers/tenancy.rb's note). after_initialize runs
# for the server, rake tasks, and job workers alike, and before any request/
# job that would run the sync.
#
# Skipped in test: the sync specs manage their own UM_API_* ENV via WebMock
# stubs (spec/support/um_api_stubs.rb), and CI has no master key to decrypt
# credentials anyway.
Rails.application.config.after_initialize do
  UmApiCredentials.install! unless Rails.env.test?
end
