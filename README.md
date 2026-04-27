# ModelRails

A multi-tenant SaaS starter kit built on Rails 8.1.

## Tech Stack

- **Framework:** Rails 8.1, Ruby 4.0
- **Database:** SQLite
- **Frontend:** TailwindCSS 4, Turbo, Stimulus
- **Assets:** Propshaft, Importmaps
- **Auth:** Rails 8 authentication generator, magic links, OmniAuth (Google, GitHub), Pundit
- **Real-Time:** Turbo Stream broadcasts (morph-based refresh)
- **Content:** Action Text (Trix rich text editor)
- **Docs:** Markdowndocs engine at `/docs`
- **Testing:** RSpec, FactoryBot, Capybara, Playwright, Bullet (N+1 detection)
- **Security:** Rate limiting, security headers, CSP, Pwned password check
- **Version Management:** [mise](https://mise.jdx.dev/) (see `.tool-versions`)

## Setup

### Prerequisites

- [mise](https://mise.jdx.dev/) (or asdf) for runtime version management
- Chromium (installed automatically by Playwright for system tests)

### Getting started

```bash
# Install Ruby and Node versions from .tool-versions
mise install

# Install dependencies, prepare database, start server
bin/setup
```

Or step by step:

```bash
bundle install
bin/rails db:prepare
bin/dev
```

### Running tests

```bash
bundle exec rspec
```

With documentation output:

```bash
bundle exec rspec --format documentation
```

Coverage report is generated at `coverage/index.html`.

### OAuth configuration

Google and GitHub OAuth require credentials. Add them via Rails credentials:

```bash
bin/rails credentials:edit
```

Add the following structure:

```yaml
google:
  client_id: your_google_client_id
  client_secret: your_google_client_secret

github:
  client_id: your_github_client_id
  client_secret: your_github_client_secret
```

OAuth is optional — email/password sign-up works without it.

## What's included (Phase 1)

### Authentication
- Smart sign-in: single email field routes users to the right auth method
  - Existing user with password → password form (with "send magic link instead" option)
  - Existing passwordless user → magic link sent automatically
  - Unknown email → registration magic link sent
- Magic link sign-in with 15-minute token expiry and one-time use
- Passwordless registration via magic link (name-only form, no password required)
- Email/password sign-up with 12-character minimum and Pwned password breach detection
- Account locking after 5 failed attempts (1-hour auto-unlock)
- Password reset using Rails 8.1 signed tokens (15-minute expiry)
- Email verification with 24-hour token expiry
- Turbo Frame inline transitions (check-email confirmation replaces form in-place)

### OAuth
- Google and GitHub sign-in via OmniAuth
- Automatic account linking by email for new OAuth signups (matches verified existing users)
- Signed-in users can link additional providers; if the OAuth-returned email matches the user's primary email, the link auto-verifies, otherwise a verification email is sent to the OAuth address and the link stays pending until clicked
- Pending OAuth authentications cannot sign in. Users can resend the confirmation email (rate-limited per user) or cancel the pending link from connected accounts
- 24-hour token expiry on verification links; cross-user collision blocked; per-user rate limit on resend
- OAuth-only users can add email/password sign-in

### Account management
- Profile editing (name, email)
- Avatar upload (Active Storage) with Gravatar fallback
- Connected accounts view with last-verified-method protection (can't remove the only verified sign-in method; pending auths can always be cancelled)
- Theme preferences (light, dark, system) with Stimulus controller and Turbo Stream updates

### UI
- All text via I18n locale files (no hardcoded strings)
- WCAG 2.2 AAA contrast ratios
- Skip-to-content link, semantic HTML landmarks
- 44px minimum touch targets on interactive elements
- Dark mode support throughout
- Accessible forms with labels, ARIA attributes, and focus rings

### Static pages
- Home, About, Privacy, Contact

## Development

### Project structure

```
app/
  controllers/
    account/                          # Profile, avatar, passwords, theme, connected accounts
    concerns/
      authenticatable.rb              # Rails 8 auth concern
    sessions_controller.rb            # Smart lookup + password sign-in
    magic_links_controller.rb         # Request a magic link
    magic_link_sessions_controller.rb # Consume magic link token (existing user)
    magic_link_registrations_controller.rb  # Passwordless registration via magic link
    registrations_controller.rb
    passwords_controller.rb
    email_verifications_controller.rb
    omniauth_callbacks_controller.rb
    pages_controller.rb
  models/
    user.rb               # Core user with has_secure_password (optional password)
    session.rb            # DB-backed sessions
    magic_link_token.rb   # Secure tokens for passwordless sign-in and registration
    authentication.rb     # Multi-provider identity (email, Google, GitHub)
    user_preferences.rb   # Theme, locale, timezone
  mailers/
    authentication_mailer.rb  # Verification + password reset emails
    magic_link_mailer.rb      # Sign-in and registration magic link emails
```

### Test suite

Tests are organized by type:

- `spec/models/` — Model validations, associations, business logic
- `spec/requests/` — Controller/integration tests
- `spec/system/` — Browser tests with Playwright
- `spec/mailers/` — Mailer content and delivery tests
