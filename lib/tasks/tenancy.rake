namespace :tenancy do
  # Mint a fresh, short-lived sign-in link for the bootstrap owner *on demand*,
  # at the moment the operator is ready to use it. The :shared seed deliberately
  # does NOT log a password token (a live credential lingering in log retention);
  # it points here instead. The token's expiry clock starts now, not at deploy.
  #
  # Usage: rails tenancy:owner_setup_link[owner@example.com]
  #        (falls back to TENANCY_OWNER_EMAIL). Set APP_HOST for the URL host.
  desc "Print a fresh short-lived sign-in link for the bootstrap owner"
  task :owner_setup_link, [ :email ] => :environment do |_t, args|
    email = args[:email].presence || ENV["TENANCY_OWNER_EMAIL"].presence
    abort "Usage: rails tenancy:owner_setup_link[owner@example.com] (or set TENANCY_OWNER_EMAIL)" if email.blank?

    owner = User.find_by!(email_address: email)
    host = ENV.fetch("APP_HOST", "localhost")
    token = MagicLinkToken.create_for_email(owner.email_address, intent: "set_password")
    url = Rails.application.routes.url_helpers.magic_link_callback_url(token: token, host: host)
    puts "[tenancy] Sign-in link for #{email} (valid 15 minutes): #{url}"
  rescue ActiveRecord::RecordNotFound
    abort "User not found: #{email}"
  end
end
