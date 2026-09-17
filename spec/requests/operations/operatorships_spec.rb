require "rails_helper"

RSpec.describe "Operations operatorships", type: :request do
  let(:operator) { create(:user, first_name: "Opal", last_name: "Operator").tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  it "lists kept operators with who granted them" do
    granter = create(:user, first_name: "Gil", last_name: "Granter")
    second = create(:user, first_name: "Sam", last_name: "Second")
    Operatorship.grant!(user: second, granted_by: granter)

    get operations_operatorships_path
    html = Capybara.string(response.body)
    expect(html).to have_text("Opal Operator")
    expect(html).to have_text("Sam Second")
    expect(html).to have_text("Gil Granter")
  end

  # The roster's whole job is who-granted-what-when, so N identically-named
  # "Revoke" buttons need distinct accessible names — the same precedent
  # (settings/sessions, settings/passkeys) this view already cites for its
  # button classes carries an aria-label too. Capybara's
  # has_button? aria-label matching needs Capybara.enable_aria_label, which
  # this suite doesn't set (see spec/system/docs_spec.rb) — Nokogiri directly,
  # matching spec/requests/settings/passkeys_spec.rb's own aria-label assertion.
  it "gives each Revoke button a name distinguishing which operator it revokes" do
    second = create(:user, first_name: "Sam", last_name: "Second")
    Operatorship.grant!(user: second)

    get operations_operatorships_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('[aria-label="Revoke Opal Operator\'s operator access"]')).to be_present
    expect(doc.at_css('[aria-label="Revoke Sam Second\'s operator access"]')).to be_present
  end

  # The machine-readable <time datetime="...iso8601"> mirrors
  # activity_logs/_activity_log.html.erb, one directory over. datetime is
  # not announced by screen readers or shown by browsers, so the VISIBLE
  # date must be asserted too — a roster whose whole job is
  # who-granted-what-when needs the date for every human and every AT user.
  # Both assertions matter: datetime alone would pass even with the visible
  # text reading "about 6 months ago".
  it "renders the grant date in a machine-readable <time> element, with the date visible as its content" do
    operatorship = Operatorship.kept.find_by!(user: operator)

    get operations_operatorships_path
    html = Capybara.string(response.body)
    expect(html).to have_css("time[datetime=\"#{operatorship.created_at.iso8601}\"]",
      text: I18n.l(operatorship.created_at.to_date))
  end

  describe "POST /operations/operatorships" do
    it "grants by email with the current operator as granter" do
      user = create(:user)
      expect {
        post operations_operatorships_path, params: { email: user.email_address }
      }.to change { user.reload.operator? }.to(true)
      expect(user.operatorships.kept.sole.granted_by).to eq(operator)
      expect(flash[:notice]).to eq(I18n.t("operations.operatorships.create.success"))
    end

    it "reports an unknown email" do
      post operations_operatorships_path, params: { email: "nobody@example.com" }
      expect(response).to redirect_to(operations_operatorships_path)
      expect(flash[:alert]).to eq(I18n.t("operations.operatorships.create.not_found"))
    end

    # A blank submission must not fall through to the not_found branch and
    # blame an email that was never entered. Own branch, own
    # posture-neutral copy — doesn't say whether an account exists.
    it "does not blame the email for a blank submission" do
      post operations_operatorships_path, params: { email: "" }
      expect(response).to redirect_to(operations_operatorships_path)
      expect(flash[:alert]).to eq(I18n.t("operations.operatorships.create.blank"))
    end

    it "says so when the user is already an operator" do
      user = create(:user)
      Operatorship.grant!(user: user)

      post operations_operatorships_path, params: { email: user.email_address }

      expect(response).to redirect_to(operations_operatorships_path)
      expect(flash[:notice]).to eq(I18n.t("operations.operatorships.create.already"))
      expect(user.operatorships.kept.count).to eq(1)
    end

    # The operator? pre-check above cannot close the window between two
    # requests' reads and the partial unique index on
    # operatorships.user_id — a double submit still reaches
    # Operatorship.grant! twice. Forcing user.operator? to always read false
    # (rather than threading real concurrency through a single-process spec)
    # simulates that race window deterministically: both requests see "not
    # yet an operator" and both attempt the grant, so the second one's
    # ActiveRecord::RecordNotUnique is what this proves gets handled.
    it "handles a double submit for the same email without raising" do
      user = create(:user)
      allow(user).to receive(:operator?).and_return(false)
      allow(User).to receive(:find_by).with(email_address: user.email_address).and_return(user)

      expect {
        2.times { post operations_operatorships_path, params: { email: user.email_address } }
      }.not_to raise_error

      expect(response).to redirect_to(operations_operatorships_path)
      expect(Operatorship.kept.where(user: user).count).to eq(1)
    end
  end

  describe "DELETE /operations/operatorships/:id" do
    it "revokes another operator" do
      other = create(:user)
      operatorship = Operatorship.grant!(user: other)
      delete operations_operatorship_path(operatorship)
      expect(other.reload).not_to be_operator
      expect(operatorship.reload).to be_discarded
      expect(flash[:notice]).to eq(I18n.t("operations.operatorships.destroy.success"))
    end

    # An operator revoking their OWN row would otherwise redirect into
    # require_operator's 404 (they're no longer one) with the flash never
    # rendered — a blank page indistinguishable from a crash.
    it "refuses to let an operator revoke their own access, and the page is still reachable after" do
      Operatorship.grant!(user: create(:user)) # not the last operator: isolates self-revoke from that refusal
      own = operator.operatorships.kept.sole
      delete operations_operatorship_path(own)
      expect(operator.reload).to be_operator
      expect(own.reload).to be_kept
      expect(flash[:alert]).to eq(I18n.t("operations.operatorships.destroy.self_revoke"))
      expect(response).to redirect_to(operations_operatorships_path)

      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "refuses to revoke the last operator" do
      own = operator.operatorships.kept.sole
      delete operations_operatorship_path(own)
      expect(operator.reload).to be_operator
      expect(flash[:alert]).to eq(I18n.t("operations.operatorships.destroy.last_operator"))
    end

    # DELETE resolves through an unscoped find, not the `kept` scope: a
    # replayed delete must reach revoke_by_operator!'s own idempotence
    # guard instead of 404ing before it can answer — the unscoped find lets
    # the second request find the already-discarded row instead of raising.
    it "does not raise on a double submit for the same operatorship" do
      other = create(:user)
      operatorship = Operatorship.grant!(user: other)

      expect {
        2.times { delete operations_operatorship_path(operatorship) }
      }.not_to raise_error

      expect(response).to redirect_to(operations_operatorships_path)
      expect(operatorship.reload).to be_discarded
      expect(ActivityLog.where(action: "operatorship.revoked", trackable: other).count).to eq(1)
      # The replay must say what actually happened. Conflating "already
      # revoked" with "that is the last operator" tells the operator their
      # click was refused on a rule that did not apply — and there are two
      # operators here, so the last_operator message would be a plain lie.
      expect(flash[:alert]).to eq(I18n.t("operations.operatorships.destroy.already_revoked"))
    end
  end
end
