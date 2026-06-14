# frozen_string_literal: true

# Single source for transactional-email colors. Email clients can't use the
# app's design tokens (no CSS custom properties, no OKLCH), so these are the
# sRGB twin of the design system's neutral ramp + interactive color, defined
# once. Mailer templates reference them inline; a fork rebrands its email
# colors here in one place. See #297.
module MailerTheme
  TEXT           = "#1f2937"  # primary body text + headings
  SUBTLE         = "#374151"  # lightly de-emphasized body (e.g. "what is this?")
  MUTED          = "#4b5563"  # footnotes / meta
  INTERACTIVE    = "#1e40af"  # buttons + links
  ON_INTERACTIVE = "#ffffff"  # text on an interactive fill
  BORDER         = "#e5e7eb"  # dividers / borders
end
