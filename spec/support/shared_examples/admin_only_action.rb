# MiClassrooms Phase 4 Task 7 (Brief §5.3): the first admin-only mutation in
# the phase — the standard Pundit denial proof (redirect + alert) factored out
# so every future admin action (building edit, bulk upload commit, role
# grants — see Curation::Apply's own header comment) can reuse it instead of
# re-deriving the same three assertions per controller.
#
# Caller must provide, via `let`:
#   workspace     - the request's tenant workspace (redirect target)
#   actor         - the signed-in, non-admin user issuing the request
#   http_method   - the verb to issue (:get, :patch, ...)
#   request_path  - the path to request
# Optionally:
#   request_params - params hash for the request (defaults to {})
RSpec.shared_examples "an admin-only action" do
  it "denies a non-admin with the standard not-authorized redirect + alert" do
    sign_in(actor)

    send(http_method, request_path, params: (defined?(request_params) ? request_params : {}))

    expect(response).to redirect_to(workspace_path(workspace))
    expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
  end
end
