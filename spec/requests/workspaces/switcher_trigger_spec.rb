require "rails_helper"

RSpec.describe "Workspace switcher trigger", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  it "names the workspace on every shell page, not only the Overview" do
    [ workspace_path(workspace), edit_workspace_path(workspace) ].each do |path|
      get path
      trigger = Nokogiri::HTML(response.body).at_css("#workspace-switcher-button")
      expect(trigger).not_to be_nil, "#{path}: no switcher trigger"
      expect(trigger.text).to include("Acme"), "#{path}: trigger does not name the workspace"
    end
  end

  # The trigger is a <button>, so anything focusable inside it is a
  # nested-interactive axe failure. The name used to be an <a> (the old identity
  # bar's link); when the id moved into this button, the rename broadcast kept
  # injecting that anchor and every personal-workspace rename audit went red.
  it "renders no focusable element inside the trigger button" do
    get workspace_path(workspace)
    trigger = Nokogiri::HTML(response.body).at_css("#workspace-switcher-button")

    expect(trigger.css("a, button, input, select, textarea, [tabindex]")).to be_empty,
      "focusable descendants nest interactive controls: #{trigger.css('a, button, input, select, textarea, [tabindex]').map(&:name)}"
  end

  # #1077: phones get the switcher in the content column. The sidebar copy is
  # display:none below md, not absent, so the mobile copy carries its own id
  # suffix on the trigger, the menu, and both inner ids — otherwise every one
  # of them is duplicated in the DOM at every width.
  it "renders a mobile trigger with its own ids, and no id on the page twice" do
    get workspace_path(workspace)
    doc = Nokogiri::HTML(response.body)

    expect(doc.at_css("#workspace-switcher-button-mobile")).not_to be_nil, "no mobile trigger"
    expect(doc.at_css("#workspace-switcher-button")).not_to be_nil, "desktop trigger lost"

    ids = doc.css("[id]").map { |el| el["id"] }
    duplicates = ids.tally.select { |_, n| n > 1 }.keys
    expect(duplicates).to be_empty, "ids present more than once: #{duplicates.inspect}"
  end

  # Opened from the keyboard there is no pointer hover, so the open state has to
  # key off aria-expanded — the pair UI::MenubarMenuComponent already uses.
  it "shows its open state without a pointer" do
    get workspace_path(workspace)
    trigger = Nokogiri::HTML(response.body).at_css("#workspace-switcher-button")

    expect(trigger["class"].split).to include("aria-expanded:bg-surface-sunken", "aria-expanded:text-text-heading")
  end

  it "re-renders BOTH triggers on rename so the phone copy cannot go stale" do
    patch workspace_path(workspace), params: { workspace: { name: "New Acme" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    doc = Nokogiri::HTML(response.body)
    %w[workspace-switcher-button workspace-switcher-button-mobile].each do |id|
      fragment = doc.at_css("##{id}")
      expect(fragment).not_to be_nil, "broadcast did not replace ##{id}"
      expect(fragment.text).to include("New Acme"), "##{id} still carries the old name"
    end
  end

  it "re-renders the whole trigger on rename, still free of focusable descendants" do
    patch workspace_path(workspace), params: { workspace: { name: "New Acme" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    fragment = Nokogiri::HTML(response.body).at_css("#workspace-switcher-button")
    expect(fragment).not_to be_nil, "expected the broadcast to replace the trigger, not a piece of it"
    expect(fragment.text).to include("New Acme")
    expect(fragment.css("a, button, input, select, textarea, [tabindex]")).to be_empty
  end
end
