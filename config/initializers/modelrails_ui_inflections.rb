# frozen_string_literal: true

# modelrails_ui components live under the UI:: namespace (e.g. UI::ButtonComponent
# in app/components/ui/button_component.rb). Register the `UI` acronym so Zeitwerk
# autoloads `ui_*.rb -> UI::*`.
#
# This lives in your app (not the gem) on purpose: modelrails_ui is a dev-only
# scaffolding gem and is not loaded in production, so the host app must own this
# inflection or production autoloading of UI:: components would fail.
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "UI"
end
