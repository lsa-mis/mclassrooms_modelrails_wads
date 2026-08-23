# The app-facing form-builder name — the fork seam. All behavior lives in the
# generated parent (app/form_builders/ui/form_builder.rb — regenerate, never
# edit; see docs/components/form_builder.md in the modelrails_ui gem). Add
# overrides here only for app-specific behavior, and fold anything generic
# upstream: the moment this class grows past a couple of methods, the seam is
# failing.
class TailwindFormBuilder < UI::FormBuilder
end
