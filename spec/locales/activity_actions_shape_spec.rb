require "rails_helper"

# #911: keys under `activity.actions` were written flat and dotted
# ("membership.created:"). I18n's nested lookup splits the requested key on "."
# and walks the hash segment by segment, so a flat dotted key is unreachable —
# and the renderer's `default:` turned every miss into a humanized column value
# with nothing raising. i18n-tasks cannot see this: it flattens nested keys to
# the same dotted form, so both shapes look identical to the static gates in
# spec/i18n_spec.rb.
#
# #1037: this lives here, not in that file. spec/i18n_spec.rb requires only
# i18n/tasks — deliberately, it is a static repo-wide scan that needs no app —
# so when it is the first file a run loads, `I18n.t` answers with a
# "translation missing" String and this example dies on NoMethodError. It
# needs Rails; the gates next door must not have it.
RSpec.describe "activity.actions locale shape" do
  it "nests every key, because a dot inside a key never resolves" do
    dotted = []
    walk = lambda do |node, path|
      node.each do |key, value|
        dotted << (path + [ key ]).join(".") if key.to_s.include?(".")
        walk.call(value, path + [ key ]) if value.is_a?(Hash)
      end
    end
    walk.call(I18n.t("activity.actions"), [])

    expect(dotted).to be_empty,
      "Flat dotted keys under activity.actions never resolve (#911): #{dotted.join(', ')}"
  end
end
