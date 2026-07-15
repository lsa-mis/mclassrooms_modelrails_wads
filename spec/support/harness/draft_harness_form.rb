# Blank ActiveModel::Model object satisfying TailwindFormBuilder's
# `object.errors` expectation for `form_with model:`. The house form
# builder's field_wrapper (used by text_field/text_area/select/check_box)
# calls `object.errors[...]` unconditionally, so a plain `form_with scope:`
# with no model (the pattern app/views/sessions/new.html.erb uses) crashes —
# that view sticks to raw `*_tag` helpers instead of `form.text_field` for
# exactly this reason. The harness needs the labeled builder helpers, so it
# supplies this no-op model instead; `scope:` in the view still controls the
# submitted param names (draft[...] / mini[...]).
class DraftHarnessForm
  include ActiveModel::Model
end
