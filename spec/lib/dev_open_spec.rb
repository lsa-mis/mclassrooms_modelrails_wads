# frozen_string_literal: true

require "rails_helper"
require "socket"
require "stringio"
require "dev_open"

RSpec.describe DevOpen do
  def quickstart = "/docs/developer/quickstart"

  def listening_server
    server = TCPServer.new("127.0.0.1", 0)
    yield server
  ensure
    server.close if server && !server.closed?
  end

  def open_page(port:, opened:, out:, env: {}, host_os: "darwin", container: false, wait: 1)
    opener = ->(cmd, url) { opened << [ cmd, url ] }
    described_class.call(port:, path: quickstart, env:, host_os:, container:, opener:, wait:, tick: 0.05, out:)
  end

  it "opens the page once the server answers" do
    listening_server do |server|
      port = server.addr[1]
      opened = []

      expect(open_page(port:, opened:, out: StringIO.new)).to eq(:opened)
      expect(opened).to eq([ [ "open", "http://localhost:#{port}#{quickstart}" ] ])
    end
  end

  it "uses xdg-open on a Linux desktop" do
    listening_server do |server|
      opened = []

      Dir.mktmpdir do |bin|
        FileUtils.touch(File.join(bin, "xdg-open"))
        File.chmod(0o755, File.join(bin, "xdg-open"))

        expect(open_page(port: server.addr[1], opened:, out: StringIO.new,
                         env: { "PATH" => bin, "DISPLAY" => ":0" }, host_os: "linux-gnu")).to eq(:opened)
        expect(opened.first.first).to eq("xdg-open")
      end
    end
  end

  it "prints the URL instead when there is no opener" do
    listening_server do |server|
      port = server.addr[1]
      opened = []
      out = StringIO.new

      expect(open_page(port:, opened:, out:, env: { "PATH" => "/nonexistent", "DISPLAY" => ":0" }, host_os: "linux-gnu")).to eq(:printed)
      expect(opened).to be_empty
      expect(out.string).to include("Open: http://localhost:#{port}#{quickstart}")
    end
  end

  it "never opens inside a container" do
    listening_server do |server|
      opened = []

      expect(open_page(port: server.addr[1], opened:, out: StringIO.new, container: true)).to eq(:printed)
      expect(opened).to be_empty
    end
  end

  it "prints a Codespace's forwarded address" do
    listening_server do |server|
      port = server.addr[1]
      out = StringIO.new
      codespace = { "CODESPACES" => "true", "CODESPACE_NAME" => "demo", "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev" }

      open_page(port:, opened: [], out:, env: codespace, container: true)

      expect(out.string).to include("Open: https://demo-#{port}.app.github.dev#{quickstart}")
    end
  end

  it "gives up quietly when the server never answers" do
    listening_server do |server|
      port = server.addr[1]
      opened = []
      out = StringIO.new
      server.close

      expect(open_page(port:, opened:, out:, wait: 0.2)).to eq(:timed_out)
      expect(opened).to be_empty
      expect(out.string).to include("http://localhost:#{port}#{quickstart}")
    end
  end
end
