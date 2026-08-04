require "rails_helper"

# Guards the Cuprite configuration in spec/support/capybara.rb against being
# silently discarded. `driven_by :cuprite` re-registers the :cuprite driver
# (Rails' SystemTesting::Driver lists :cuprite as registerable), so options set
# in a standalone Capybara.register_driver block never reach the browser — the
# suite ran on ferrum's defaults from #497 until #532. These assertions read the
# live driver, so a future refactor that drops the options fails here rather
# than as intermittent browser-launch flakes under parallel load.
RSpec.describe "Cuprite driver configuration", type: :system do
  it "gives the browser long enough to launch under parallel load" do
    # Ferrum's default is 10s (FERRUM_PROCESS_TIMEOUT); 18 concurrent workers
    # racing to spawn Chrome regularly exceed it.
    expect(page.driver.options[:process_timeout]).to eq(30)
  end

  it "tolerates non-essential connections still in flight at the goto timeout" do
    # Lookbook preview pages pull an asset-heavy harness; without this a slow
    # harness asset raises Ferrum::PendingConnectionsError and flakes a
    # component's a11y spec that has nothing to do with the harness.
    expect(page.driver.options[:pending_connection_errors]).to be false
  end

  it "does not raise on page JS console errors" do
    expect(page.driver.options[:js_errors]).to be false
  end

  it "uses the configured page timeout" do
    expect(page.driver.options[:timeout]).to eq(15)
  end

  it "sizes the browser window for the desktop layout" do
    expect(page.driver.options[:window_size]).to eq([ 1400, 1400 ])
  end

  # Chromium refuses to start as root without --no-sandbox ("Running as root
  # without --no-sandbox is not supported", crbug.com/638180), and the
  # devcontainer's remoteUser IS root — so every system spec there died with
  # `Ferrum::ProcessTimeoutError: Browser did not produce websocket url`, a
  # message that names neither root nor the sandbox. Found by #535's new
  # devcontainer CI gate.
  #
  # Scoped to root rather than applied unconditionally: --no-sandbox disables a
  # real security boundary, and on a developer's own machine (non-root) there is
  # no reason to give it up.
  describe "running as root, as in the devcontainer" do
    it "passes the flags Chromium needs to start in a container" do
      skip "only meaningful when running as root (containers)" unless Process.uid.zero?

      flags = page.driver.options[:browser_options].to_h.keys.map(&:to_s)
      expect(flags).to include("no-sandbox")
      # Docker's default /dev/shm is 64MB; Chromium exhausts it and crashes
      # mid-run, which surfaces as an unrelated-looking tab crash.
      expect(flags).to include("disable-dev-shm-usage")
    end
  end
end
