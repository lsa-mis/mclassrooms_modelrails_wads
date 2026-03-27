# ModelRails

A multi-tenant SaaS starter kit built on Rails 8.1.

## Tech Stack

- **Framework:** Rails 8.1, Ruby 4.0
- **Database:** SQLite
- **Frontend:** TailwindCSS 4, Turbo, Stimulus
- **Assets:** Propshaft, Importmaps
- **Auth:** Rails 8 authentication generator, OmniAuth (Google, GitHub), Pundit
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
- Email/password sign-up with 12-character minimum and Pwned password breach detection
- Sign in/out with Rails 8 session management
- Account locking after 5 failed attempts (1-hour auto-unlock)
- Password reset using Rails 8.1 signed tokens (15-minute expiry)
- Email verification with 24-hour token expiry

### OAuth
- Google and GitHub sign-in via OmniAuth
- Automatic account linking by email for existing users
- Signed-in users can link additional providers
- OAuth-only users can add email/password sign-in

### Account management
- Profile editing (name, email)
- Avatar upload (Active Storage) with Gravatar fallback
- Connected accounts view with unlink protection (can't remove last sign-in method)
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
    account/              # Profile, avatar, passwords, theme, connected accounts
    concerns/
      authenticatable.rb  # Rails 8 auth concern
    pages_controller.rb
    sessions_controller.rb
    registrations_controller.rb
    passwords_controller.rb
    email_verifications_controller.rb
    omniauth_callbacks_controller.rb
  models/
    user.rb               # Core user with has_secure_password
    session.rb            # DB-backed sessions
    authentication.rb     # Multi-provider identity (email, Google, GitHub)
    user_preferences.rb   # Theme, locale, timezone
  mailers/
    authentication_mailer.rb  # Verification + password reset emails
```

### Test suite

Tests are organized by type:

- `spec/models/` — Model validations, associations, business logic
- `spec/requests/` — Controller/integration tests
- `spec/system/` — Browser tests with Playwright
- `spec/mailers/` — Mailer content and delivery tests
