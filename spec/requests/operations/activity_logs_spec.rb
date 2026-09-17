require "rails_helper"

RSpec.describe "Operations activity feed", type: :request do
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  it "renders rows from several workspaces" do
    w1 = create(:workspace, name: "Alpha")
    w2 = create(:workspace, name: "Beta")
    create(:project, workspace: w1)
    create(:project, workspace: w2)

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    html = Capybara.string(response.body)
    expect(html).to have_text("Alpha")
    expect(html).to have_text("Beta")
  end

  # .btn-text sets no colour of its own — .btn-text-interactive is what
  # makes it read as a link rather than plain text (1.4.1).
  it "renders a row's workspace name link as visibly a link" do
    workspace = create(:workspace, name: "Alpha")
    create(:project, workspace: workspace)

    get operations_activity_logs_path
    link = Capybara.string(response.body).first(:link, "Alpha")
    expect(link[:class]).to include("btn-text-interactive")
  end

  # activity_logs/_activity_log renders a top-level <li>, and this page
  # wrapped each one in its own <ol> to give that <li> a legal parent —
  # making every entry a nested one-item list, which a screen reader
  # announces as "list, 1 item" on every row. Valid HTML, so axe passes it:
  # the structure has to be asserted directly.
  it "renders each row in one flat list, not a nested one-item list per row" do
    workspace = create(:workspace, name: "Alpha")
    create(:project, workspace: workspace)

    get operations_activity_logs_path
    html = Capybara.string(response.body)

    expect(html).to have_css("ol > li", text: "Alpha")
    expect(html).to have_no_css("li ol")
  end

  # Tailwind's preflight sets list-style:none on <ol>, which strips the
  # implicit list semantics Safari/VoiceOver relies on — axe has no rule for
  # this, so a clean axe run is not evidence either way.
  it "restores list semantics on the raw <ol> preflight strips" do
    create(:workspace, name: "Alpha")

    get operations_activity_logs_path
    expect(Capybara.string(response.body)).to have_css('ol[role="list"]')
  end

  it "has an index that can serve a global created_at ordering" do
    indexes = ActiveRecord::Base.connection.indexes(:activity_logs).map(&:columns)
    expect(indexes).to include([ "created_at" ])
  end

  # 20 is Pagy::OPTIONS[:limit] (config/initializers/pagy.rb); 25 distinct
  # workspaces guarantees a real second page, so the nav's locals contract is
  # actually exercised.
  it "paginates once rows cross a page boundary" do
    25.times { |i| create(:workspace, name: "WS #{i}") }

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    html = Capybara.string(response.body)
    expect(html).to have_css("nav.series-nav")
    # shared/_pagination is a card FOOTER (border-t px-4 py-3); rendered
    # after the card's closing </div> it paints a stray rule across the bare
    # page instead. Both sibling call sites nest it inside the card.
    expect(html).to have_css("div.rounded-lg nav.series-nav")
  end

  # Nothing else binds the controller to the privacy-bearing scope —
  # swapping for_operations_feed for ActivityLog.all would leave both other
  # examples green, since neither creates a personal row.
  #
  # Not a bare name-absence check: create(:user) itself onboards a personal
  # workspace and writes a legitimate membership.created row naming that same
  # user (Trackable), so the new user's own name is already on the page for a
  # reason unrelated to the row under test — asserting its absence would pass
  # or fail for the wrong reason. Binding the rendered row count to the scope's
  # own count proves the view renders exactly what the privacy-excluding scope
  # returns, which is what actually needs proving at the request level.
  it "excludes personal-visibility security rows from the feed" do
    create(:workspace)
    private_user = create(:user)
    ActivityLog.record_security_event!(action: "user.password_changed", user: private_user)

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)

    total = ActivityLog.for_operations_feed.count
    # This comparison only proves anything while the total stays under
    # Pagy's page limit — past it, the rendered count is the PAGE's count,
    # not the scope's, and the assertion below would pass or fail for a
    # reason unrelated to the privacy scope it exists to prove. Pin the
    # precondition explicitly rather than let factory or onboarding noise
    # push it over unnoticed.
    expect(total).to be < Pagy::OPTIONS[:limit]

    rendered_rows = Capybara.string(response.body).all("li time").size
    expect(rendered_rows).to eq(total)
  end

  # This page is the first surface to render admin-visibility rows, and an
  # operatorship grant's trackable is the grantee User (not a Membership),
  # so without this case the row would read "a member" instead of naming
  # anyone.
  #
  # Asserts the composed sentence, not a bare name-presence check: create(:user)
  # onboards its own workspace and writes a membership.created row that ALSO
  # names the grantee (as the member who joined) — a plain "page has text
  # 'Gale Grantee'" assertion would pass even with the bug unfixed, because
  # that unrelated row already supplies the name. The activity.actions.operatorship.granted
  # sentence ("granted %{member} operator access") is unique to this row.
  it "names the granted user on an operatorship row, not the neutral fallback" do
    grantee = create(:user, first_name: "Gale", last_name: "Grantee")
    Operatorship.grant!(user: grantee)

    get operations_activity_logs_path
    expect(Capybara.string(response.body)).to have_text("granted Gale Grantee operator access")
  end

  # operated_workspaces is Workspace.kept, so a discarded workspace's slug
  # can never resolve — but discarding one WRITES its own activity row (an
  # ordinary update!, Trackable fires), which stays in the feed forever.
  # Same guard as operations/users/show.html.erb's membership rows.
  it "does not link a row whose workspace has since been discarded" do
    workspace = create(:workspace, name: "Alpha")
    workspace.discard!

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    html = Capybara.string(response.body)
    expect(html).to have_text("Alpha")
    expect(html).to have_no_link(href: operations_workspace_path(workspace))
  end

  # activity_logs.trackable_id has no FK, so a hard-deleted User leaves a
  # dangling row; #display_member's User branch needs safe navigation, or
  # this 500s the whole feed (the row is persisted, so it can't be edited
  # away once it ships). `grantee.destroy!` produces the real dangling
  # state — update_all would fake it only because the immutability guard
  # scans {app,lib}, not spec/, imitating the symptom, not the cause.
  it "shows the neutral noun instead of raising when a User trackable is gone" do
    grantee = create(:user)
    Operatorship.grant!(user: grantee)
    grantee.destroy!

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    expect(Capybara.string(response.body)).to have_text(I18n.t("activity.unknown_member"))
  end
end
