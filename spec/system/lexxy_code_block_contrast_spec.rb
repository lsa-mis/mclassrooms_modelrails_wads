# frozen_string_literal: true

require "rails_helper"

RSpec.describe "A code block in the rich-text editor", type: :system do
  let!(:workspace) { create(:workspace, slug: "lexxy-code-block-workspace", personal: false) }
  let(:admin) do
    create(:user).tap do |user|
      Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    end
  end
  let!(:announcement) do
    create(:announcement, workspace: workspace,
      body: %(<pre data-language="ruby">def greet(name)\n  puts "Hello, \#{name}!" # say hi\nend</pre>))
  end

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    sign_in_via_form(admin)
  end

  it "highlights its syntax at AAA in both themes" do
    visit edit_admin_announcement_path(announcement)

    expect(page).to have_css("lexxy-editor .code-token__function", text: "greet")
    expect(page).to have_css("lexxy-editor .code-token__comment", text: "# say hi")
    expect_aaa_in_both_themes(include: "lexxy-editor")
  end
end
