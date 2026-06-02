# frozen_string_literal: true

# Ergonomic facade for the vendored UI::* ViewComponents. Renders a component by
# short name, hiding the `render UI::…Component.new` boilerplate so the component
# class stays an implementation detail:
#
#   ui :button, "Save", variant: :primary
#   ui(:dialog, title: "Edit profile") { "body" }
#
# Positional and keyword args forward straight to the component's initializer.
# An unknown name raises NameError — a boundary guard, in the same spirit as the
# components' own input validation.
module UIHelper
  def ui(name, *args, **kwargs, &block)
    component_class = UI.const_get("#{name.to_s.camelize}Component")
    render(component_class.new(*args, **kwargs), &block)
  end
end
