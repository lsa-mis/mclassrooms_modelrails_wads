---
title: Getting Started
description: Setup instructions and development workflow for ModelRails
---

# Getting Started

## Prerequisites

- [mise](https://mise.jdx.dev/) for runtime version management (see `.tool-versions`)
- Chromium (installed by Playwright for system tests)

## Setup

```bash
mise install        # Install Ruby and Node from .tool-versions
bin/setup           # Install deps, prepare database, start server
```

Or step by step:

```bash
bundle install
rails db:prepare
rails db:seed       # Seeds default roles
bin/dev             # Start development server
```

## Running Tests

```bash
bundle exec rspec                        # Full suite
bundle exec rspec --format documentation # Verbose output
```

Coverage report is generated at `coverage/index.html`.

## Key Commands

| Command | Purpose |
|---------|---------|
| `bin/dev` | Start development server |
| `bundle exec rspec` | Run test suite |
| `bundle exec brakeman` | Security scan |
| `rails users:unlock[email]` | Unlock a locked account |
| `rails users:verify[email]` | Manually verify an email |
| `rails users:suspend[email]` | Suspend a user |

## OAuth Setup

Add credentials for Google and GitHub OAuth:

```bash
bin/rails credentials:edit
```

```yaml
google:
  client_id: your_id
  client_secret: your_secret
github:
  client_id: your_id
  client_secret: your_secret
```
