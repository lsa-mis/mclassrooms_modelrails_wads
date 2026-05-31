# frozen_string_literal: true

# Base class for modelrails_ui components.
#
# Self-contained on purpose: the `cn` class-merge helper is inlined so your app
# carries NO runtime dependency on the modelrails_ui gem. modelrails_ui is a
# dev-only scaffolding tool (it generates these files); production loads only
# your vendored components + view_component.
class ApplicationComponent < ViewComponent::Base
  private

  # Join Tailwind class lists into one string, dropping nils and blanks.
  def cn(*classes)
    classes.flatten.compact.reject { |c| c.to_s.empty? }.join(" ")
  end
end
