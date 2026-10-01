require "rails_helper"

RSpec.describe "Operations activity feed", type: :request do
  # Fork (MClassrooms): no Project domain — a workspace's own creation row
  # (Trackable on Workspace) is what puts its name in the feed here.
  let(:operator) { create(:user).tap { |u| Operatorship.grant!(user: u) } }

  before { sign_in(operator) }

  it "renders rows from several workspaces" do
    w1 = create(:workspace, name: "Alpha")
    w2 = create(:workspace, name: "Beta")

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    html = Capybara.string(response.body)
    expect(html).to have_text("Alpha")
    expect(html).to have_text("Beta")
  end

  it "paginates without a Pagy deprecation warning" do
    expect { get operations_activity_logs_path }.not_to output(/\[PAGY\]/).to_stderr
  end

  # .btn-cell-link sets no colour of its own — .btn-text-interactive is what
  # makes it read as a link rather than plain text (1.4.1).
  it "renders a row's workspace name link as visibly a link" do
    workspace = create(:workspace, name: "Alpha")

    get operations_activity_logs_path
    link = Capybara.string(response.body).first(:link, "Alpha")
    expect(link[:class]).to include("btn-text-interactive")
  end

  # The ledger is a table, not a list: one <tr> per event, every header a
  # column header, and the caption carries the accessible name.
  it "renders each event as a table row under column headers" do
    workspace = create(:workspace, name: "Alpha")

    get operations_activity_logs_path
    html = Capybara.string(response.body)
    expect(html).to have_css("turbo-frame#activity_results tbody tr", minimum: 1)
    expect(html.all("thead th").size).to eq(html.all("thead th[scope=col]").size)
    expect(html).to have_css('thead th[aria-sort="descending"]', count: 1)
  end

  # The results count must reach a screen reader after a frame swap: the
  # status node lives OUTSIDE the frame, empty at first render, and a frame
  # response carries a turbo-stream that mutates it (the live-region rule).
  it "renders an empty status node outside the frame and streams the summary into it on frame requests" do
    create(:workspace, name: "Alpha")

    get operations_activity_logs_path
    html = Capybara.string(response.body)
    expect(html).to have_css('#activity_results_status[role="status"][aria-live="polite"]', visible: :all)
    # Not `text: ""` — an empty substring matches any text at all, so that
    # assertion passed with the summary already in the node.
    expect(html.find("#activity_results_status", visible: :all).text(:all)).to eq("")
    expect(html).to have_no_css("turbo-frame#activity_results #activity_results_status", visible: :all)
    expect(html).to have_no_css("turbo-stream", visible: :all)

    get operations_activity_logs_path, headers: { "Turbo-Frame" => "activity_results" }
    expect(Capybara.string(response.body)).to have_css('turbo-frame#activity_results turbo-stream[action="update"][target="activity_results_status"]', visible: :all)
  end

  # The two caveats that qualify what a count MEANS used to be a footnote under
  # the table; they now hang off the summary, where a surprising count is read.
  # The trigger is icon-only, so its accessible name is the assertion — an icon
  # with no name is a control nobody can ask about.
  it "offers the results caveats from the card toolbar, named and holding both sentences" do
    create(:workspace, name: "Alpha")

    get operations_activity_logs_path
    html = Capybara.string(response.body)
    trigger = html.find("button[aria-haspopup=dialog]", text: I18n.t("operations.activity_logs.index.about.label"))
    panel = html.find("##{trigger["aria-controls"]}", visible: :all)
    expect(panel[:role]).to eq("dialog")
    expect(panel).to have_text(I18n.t("operations.activity_logs.index.about.best_effort"))
    expect(panel).to have_text(I18n.t("operations.activity_logs.index.about.derived"))
  end

  # An empty result is the one state where "absence is not proof" has to be
  # read without opening anything, so that sentence is on the card itself —
  # and the caveats control is still reachable when a filter matched nothing.
  it "states the best-effort caveat on the empty state, inside the frame" do
    get operations_activity_logs_path(person: "nobody@example.com")
    html = Capybara.string(response.body)
    frame = html.find("turbo-frame#activity_results")
    expect(frame).to have_text(I18n.t("operations.activity_logs.index.empty"))
    expect(frame).to have_text(I18n.t("operations.activity_logs.index.about.best_effort"))
    expect(frame).to have_css("button[aria-haspopup=dialog]", text: I18n.t("operations.activity_logs.index.about.label"))
  end

  # The hint moved onto the control it qualifies: aria-describedby is what
  # makes it reach a screen-reader user at the moment they type, which a page
  # footnote never did.
  it "describes the search field with what it matches" do
    get operations_activity_logs_path
    html = Capybara.string(response.body)
    expect(html.find("#q")["aria-describedby"]).to eq("q-hint")
    expect(html.find("#q-hint", visible: :all).text(:all))
      .to eq(I18n.t("operations.activity_logs.index.filters.search_hint"))
  end

  it "has an index that can serve a global created_at ordering" do
    indexes = ActiveRecord::Base.connection.indexes(:activity_logs).map(&:columns)
    expect(indexes).to include([ "created_at" ])
  end

  # The ledger's own default is 50 rows (ActivityLogsController::DEFAULT_ROWS),
  # not Pagy::OPTIONS[:limit]; 55 distinct workspaces guarantees a real second
  # page, so the nav's locals contract is actually exercised.
  it "paginates once rows cross a page boundary" do
    55.times { |i| create(:workspace, name: "WS #{i}") }

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    html = Capybara.string(response.body)
    # Inside the frame: the pager swaps the results, so a nav rendered outside
    # it would page a region that never changes.
    expect(html).to have_css("turbo-frame#activity_results nav.series-nav")
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
    # This comparison only proves anything while the total stays under the
    # ledger's default page size — past it, the rendered count is the PAGE's
    # count, not the scope's, and the assertion below would pass or fail for a
    # reason unrelated to the privacy scope it exists to prove. Pin the
    # precondition explicitly rather than let factory or onboarding noise
    # push it over unnoticed.
    expect(total).to be < 50

    rendered_rows = Capybara.string(response.body).all("tbody tr time").size
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

  # Fork (MClassrooms): admin curation rows (Curation::Apply, visibility
  # "admin") reached no feed until this one existed, and a missing
  # activity.actions label raises under raise_on_missing_translations — an
  # operator's page would 500 the first time an admin curated anything.
  # Every action the admin controllers hand Curation::Apply needs a label.
  it "labels every fork curation action this feed can render" do
    sources = Dir[Rails.root.join("app/controllers/admin/**/*.rb")] + Dir[Rails.root.join("app/lib/**/*.rb")]
    actions = sources.flat_map { |f| File.read(f).scan(/action: "([a-z_]+\.[a-z_]+)"/).flatten }.uniq
    expect(actions).not_to be_empty

    missing = actions.reject { |a| I18n.exists?("activity.actions.#{a}") }
    expect(missing).to be_empty, "curation actions without an activity.actions label: #{missing.join(", ")}"
  end

  it "renders a fork curation row with its label instead of raising" do
    workspace = create(:workspace, name: "Alpha")
    ActivityLog.create!(actor: operator, action: "announcement.created", trackable: workspace,
                        workspace: workspace, visibility: "admin")

    get operations_activity_logs_path
    expect(response).to have_http_status(:ok)
    expect(Capybara.string(response.body)).to have_text(I18n.t("activity.actions.announcement.created"))
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
