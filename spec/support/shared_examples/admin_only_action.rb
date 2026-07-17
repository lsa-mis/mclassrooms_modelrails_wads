# MiClassrooms Phase 4 Task 7 (Brief §5.3): the first admin-only mutation in
# the phase — the standard Pundit denial proof (redirect + alert) factored out
# so every future admin action (building edit, bulk upload commit, role
# grants — see Curation::Apply's own header comment) can reuse it instead of
# re-deriving the same three assertions per controller.
#
# Caller must provide, via `let`:
#   actor         - the signed-in, non-admin MEMBER (viewer/editor) issuing the request
#   http_method   - the verb to issue (:get, :patch, ...)
#   request_path  - the path to request
# Optionally:
#   request_params - params hash for the request (defaults to {})
#
# Redirect target: since the workspace dashboard became admin-only
# (WorkspacePolicy#show?, 2026-07-17), a denied non-admin member lands on
# Find a Room — the product home they CAN reach — not /workspaces/:slug (which
# would loop). All callers sign in a viewer/editor member, so that is the
# uniform destination; see ApplicationController#not_authorized_redirect_path.
RSpec.shared_examples "an admin-only action" do
  it "denies a non-admin with the standard not-authorized redirect + alert" do
    sign_in(actor)

    send(http_method, request_path, params: (defined?(request_params) ? request_params : {}))

    expect(response).to redirect_to(find_a_room_path)
    expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
  end
end
