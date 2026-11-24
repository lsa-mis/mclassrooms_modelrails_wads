# frozen_string_literal: true

require "rails_helper"
require "socket"
require "dev_port"

RSpec.describe DevPort do
  let(:listeners) { [] }

  after { listeners.each(&:close) }

  def listen(host = "127.0.0.1", port = 0)
    TCPServer.new(host, port).tap { |server| listeners << server }.addr[1]
  end

  def busy_run(length)
    20.times do
      base = free_port
      taken = []
      begin
        length.times { |i| taken << TCPServer.new("127.0.0.1", base + i) }
        listeners.concat(taken)
        return base
      rescue Errno::EADDRINUSE, Errno::EACCES
        taken.each(&:close)
      end
    end
    raise "no run of #{length} free ports found"
  end

  describe ".busy?" do
    it "treats a port listened on at 127.0.0.1 as busy" do
      expect(described_class.busy?(listen)).to be(true)
    end

    it "treats a port listened on at ::1 only as busy" do
      expect(described_class.busy?(listen("::1"))).to be(true)
    end

    it "treats a port listened on at 0.0.0.0 as busy" do
      expect(described_class.busy?(listen("0.0.0.0"))).to be(true)
    end

    it "treats a port nothing listens on as free" do
      expect(described_class.busy?(free_port)).to be(false)
    end
  end

  describe ".choose" do
    it "returns a free port unchanged" do
      port = free_port

      expect(described_class.choose(port, explicit: false, container: false)).to eq(port)
    end

    it "moves a busy default port to the next free one" do
      port = busy_run(1)

      expect(described_class.choose(port, explicit: false, container: false)).to eq(port + 1)
    end

    it "refuses a busy explicit port in one line" do
      port = listen

      expect { described_class.choose(port, explicit: true, container: false) }
        .to raise_error(DevPort::Busy) { |error|
          expect(error.message.lines.size).to eq(1)
          expect(error.message).to include(port.to_s)
        }
    end

    it "never moves inside a container" do
      port = listen

      expect { described_class.choose(port, explicit: false, container: true) }.to raise_error(DevPort::Busy, /#{port}/)
    end

    it "gives up after ten busy ports" do
      port = busy_run(11)

      expect { described_class.choose(port, explicit: false, container: false) }.to raise_error(DevPort::Busy)
    end
  end

  describe ".container?" do
    it "is true in a Codespace, a VS Code dev container, or a Docker container" do
      expect(described_class.container?({ "CODESPACES" => "true" })).to be(true)
      expect(described_class.container?({ "REMOTE_CONTAINERS" => "true" })).to be(true)
      expect(described_class.container?({}, dockerenv: true)).to be(true)
    end

    it "is false on a plain machine" do
      expect(described_class.container?({}, dockerenv: false)).to be(false)
    end
  end

  describe ".announcement" do
    it "announces localhost URLs outside Codespaces" do
      expect(described_class.announcement(3001, {})).to include("http://localhost:3001/docs/developer/quickstart")
    end

    it "announces the forwarded URL in Codespaces" do
      env = { "CODESPACES" => "true", "CODESPACE_NAME" => "demo", "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev" }

      expect(described_class.announcement(3000, env)).to include("https://demo-3000.app.github.dev/docs/developer/quickstart")
      expect(described_class.announcement(3000, env)).not_to include("localhost")
    end
  end
end
