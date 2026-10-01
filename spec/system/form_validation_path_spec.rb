require "rails_helper"

# A malformed email reaches the server's error summary, not a native bubble
# (#1117). A system spec, because the defect is what a browser does first.
RSpec.describe "Form validation path", type: :system do
  let(:operator) { create(:user, :with_zero_workspaces).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in_via_form(operator) }

  it "sends a malformed email to the server, which answers with its own error summary" do
    visit new_operations_workspace_path

    fill_in I18n.t("operations.workspaces.new.name"), with: "New Co"
    fill_in I18n.t("operations.workspaces.new.owner_email"), with: "not-an-email"
    click_button I18n.t("operations.workspaces.new.submit")

    # Only a rendered 422 has the summary, and the builder sets aria-invalid.
    expect(page).to have_text(I18n.t("activerecord.errors.models.workspace.attributes.owner_email.invalid"))
    field = find_field(I18n.t("operations.workspaces.new.owner_email"), with: "not-an-email")
    expect(field["aria-invalid"]).to eq("true")
    expect(Workspace.find_by(name: "New Co")).to be_nil
  end
end
