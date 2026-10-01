require "rails_helper"

# Forms must reach FormDefaultsHelper#form_with, which adds novalidate (#1117):
# no form_for/form_tag, and components call helpers.form_with. button_to is exempt.
RSpec.describe "Code smell: forms route through form_with" do
  let(:bypass_anywhere) { /\bform_(?:for|tag)\b/ }
  let(:bypass_in_component) { /(?<!helpers\.)\bform_with\b/ }

  # POSITIVE CONTROL: an empty list is also what a broken pattern produces.
  it "recognises every spelling it claims to cover" do
    expect("<%= form_for @user do |f| %>").to match(bypass_anywhere)
    expect("<%= form_tag '/x' do %>").to match(bypass_anywhere)
    expect("form_with(model: record)").to match(bypass_in_component)

    expect("helpers.form_with(model: record)").not_to match(bypass_in_component),
      "helpers.form_with goes through the view context and must stay allowed"
    expect("<%= form_with model: @user do |f| %>").not_to match(bypass_anywhere)
  end

  def offenders(glob, pattern)
    Dir[Rails.root.join(glob)].flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      File.readlines(file).each_with_index.filter_map do |line, i|
        "#{relative}:#{i + 1}: #{line.strip}" if line.match?(pattern)
      end
    end
  end

  it "builds no form with form_for or form_tag" do
    found = offenders("app/{views,components,helpers}/**/*.{erb,rb}", bypass_anywhere)

    expect(found).to be_empty, <<~MSG
      These build a <form> without form_with, so they skip FormDefaultsHelper and
      the browser's native validation runs again -- a malformed email is blocked
      by a transient bubble instead of reaching the server's error summary:

        #{found.join("\n  ")}

      Use form_with.
    MSG
  end

  it "calls form_with from no ViewComponent except through helpers" do
    found = offenders("app/components/**/*.{erb,rb}", bypass_in_component)

    expect(found).to be_empty, <<~MSG
      A component calling form_with directly gets ActionView's method, not the
      app's helper, so its form renders without novalidate:

        #{found.join("\n  ")}

      Call helpers.form_with instead.
    MSG
  end
end
