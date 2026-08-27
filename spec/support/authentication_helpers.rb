module AuthenticationHelpers
  include ActionMailer::TestHelper

  # Establish a browser session via the magic-link callback. For system specs,
  # where the session cookie must live in the driven browser, not the
  # Rack::Test cookie jar. Canonical home (#743).
  #
  # EXACTLY ONE PARTY MINTS THE TOKEN, and that is the whole design.
  #
  # `MagicLinkToken.create_for_email` supersedes every prior unconsumed token
  # for an address — a partial unique index enforces one live token per email.
  # This helper used to open with the request-a-link form, so the app minted a
  # token and then the test minted a second, competing for that one slot with
  # nothing but a rendered-text assertion for ordering. Whenever the app's mint
  # landed second, the token about to be clicked was already dead; the callback
  # rejected it and, since the session had begun, redirected to root_path —
  # the signed-in homepage carrying "invalid or has expired" that CI reported
  # in #846, and in #796 three days before that.
  #
  # #796 answered it with `wait: 10`. A timeout cannot fix a data race: it only
  # bets on which writer finishes first. Removing the second writer does fix
  # it, and the prelude was never load-bearing here — requesting a link through
  # the form is the SUBJECT of magic_link_sign_in_spec, and merely the setup
  # cost of everyone else.
  #
  # spec/system/sign_in_helper_contract_spec.rb pins the one-mint property, so
  # a returning prelude fails there by name rather than intermittently in an
  # unrelated caller.
  def sign_in_via_form(user)
    token = MagicLinkToken.create_for_email(user.email_address)
    visit magic_link_callback_path(token: token)
    click_button I18n.t("magic_link_callbacks.confirm.sign_in_button")
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
  end

  # Drive the lookup form and hand back the token the app minted, read out of
  # the mail it sent — the way a recipient actually gets it.
  #
  # For specs where requesting the link is part of the SUBJECT, not setup.
  # `sign_in_via_form` is the right tool for setup; this is the tool for the
  # handful of specs that must show the form working. Either way exactly one
  # party mints: there, the test; here, the app.
  #
  # The token never reaches the database in recoverable form (only its digest
  # is stored), so the mail is the only place to read it back — which is why
  # these specs used to mint a second token instead, and why they raced (#849).
  def request_magic_link(email)
    perform_enqueued_jobs do
      fill_in I18n.t("sessions.new.email_label"), with: email
      click_button I18n.t("sessions.new.continue")
      expect(page).to have_text(I18n.t("sessions.check_email.title"))
    end

    magic_link_token_from_email(email)
  end

  # Fails loudly and by name: a nil token here would otherwise surface as an
  # unrelated routing error at the callback.
  def magic_link_token_from_email(email)
    address = email.downcase
    mail = ActionMailer::Base.deliveries.reverse.find { |m| m.to&.include?(address) }
    raise "No magic-link mail was delivered to #{address}" if mail.nil?

    body = (mail.text_part || mail.html_part || mail).body.decoded
    body[%r{/magic_link_callback/([A-Za-z0-9_-]+)}, 1] ||
      raise("Mail to #{address} carried no magic-link callback URL")
  end

  def sign_in(user)
    if user.has_password?
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }
    else
      # Passwordless users cannot authenticate via password form; create session directly
      # by generating a properly signed session_id cookie matching ActionDispatch's format.
      # Mirror start_new_session_for: a just-signed-in session is active and
      # reauth-fresh, so lifecycle/reauth gates behave as they do in production.
      session_record = user.sessions.create!(
        user_agent: "RSpec", ip_address: "127.0.0.1",
        last_active_at: Time.current, reauthenticated_at: Time.current
      )
      env = Rails.application.env_config
      salt = env["action_dispatch.signed_cookie_salt"]
      secret = env["action_dispatch.key_generator"].generate_key(salt)
      verifier = ActiveSupport::MessageVerifier.new(
        secret,
        digest: "SHA1",
        serializer: ActiveSupport::MessageEncryptor::NullSerializer
      )
      signed_value = verifier.generate(session_record.id.to_s, purpose: "cookie.session_id")
      cookies[:session_id] = signed_value
    end
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
  config.include AuthenticationHelpers, type: :system
end
