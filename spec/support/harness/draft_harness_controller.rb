# Test-only controller backing /draft_harness (routes.rb gates it to test).
# Inherits the app's authentication so the form-draft key meta is delivered.
# No Pundit policy: this is a static harness page, not a tenant-scoped
# resource, so there is nothing to authorize.
class DraftHarnessController < ApplicationController
  prepend_view_path Rails.root.join("spec/support/harness/views")

  def show
    @errors = []
    @harness_form = DraftHarnessForm.new
  end

  def create
    if params[:pass] == "1"
      redirect_to draft_harness_path, notice: "Saved"
    else
      @errors = [ "Title is invalid" ]
      @harness_form = DraftHarnessForm.new
      render :show, status: :unprocessable_content
    end
  end
end
