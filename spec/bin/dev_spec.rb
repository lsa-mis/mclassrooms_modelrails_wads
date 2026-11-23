# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "socket"
require "dev_port"

RSpec.describe "bin/dev" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = Pathname.new(dir)
      stubs = @dir.join("stubs")
      stubs.mkpath
      { "gem" => "exit 0", "foreman" => %[echo "DEV_SERVER_PORT=$DEV_SERVER_PORT"; echo "$@"; exec "#{RbConfig.ruby}" -e 'begin; Process.wait(-1); puts "FOREMAN_CHILD_EXITED"; rescue Errno::ECHILD; end'],
        "ruby" => %[case "$1" in *dev_open.rb) echo "$@" > "#{@dir.join('opened')}" ;; *) exec "#{RbConfig.ruby}" "$@" ;; esac] }.each do |name, body|
        stubs.join(name).write("#!/bin/sh\n#{body}\n")
        stubs.join(name).chmod(0o755)
      end
      example.run
    end
  end

  def capture_dev(*args, env: {})
    path = "#{@dir.join('stubs')}:#{ENV.fetch('PATH')}"
    Open3.capture2e({ "PATH" => path, "PORT" => nil, "DEV_SERVER_PORT" => nil, "CODESPACES" => nil, "REMOTE_CONTAINERS" => nil, "DEV_OPEN_PATH" => nil }.merge(env),
                    Rails.root.join("bin/dev").to_s, *args, chdir: @dir.to_s)
  end

  def run_dev(*args, env: {})
    output, status = capture_dev(*args, env:)
    expect(status).to be_success, output
    lines = output.lines.map(&:strip)
    exported = lines.index { |line| line.start_with?("DEV_SERVER_PORT=") }
    [ lines[exported].delete_prefix("DEV_SERVER_PORT="), lines[exported + 1] ]
  end

  it "exports the web port as DEV_SERVER_PORT and starts foreman on it" do
    skip "3000 is in use inside a container, where bin/dev refuses it, as the busy -p example shows" if DevPort.container?({}) && DevPort.busy?(3000)
    port = DevPort.choose(3000, explicit: false, container: DevPort.container?({}))

    expect(run_dev).to eq([ port.to_s, "start -f Procfile.dev --port #{port}" ])
  end

  it "refuses a busy port given with -p, without a stack trace" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]

    output, status = capture_dev("-p", port.to_s)

    expect(status).not_to be_success
    expect(output.lines.size).to eq(1)
    expect(output).to include(port.to_s)
    expect(output).not_to include("EADDRINUSE")
  ensure
    server&.close
  end

  it "prints the app and quickstart URLs before starting foreman" do
    port = free_port

    output, = capture_dev("-p", port.to_s)

    expect(output).to include("http://localhost:#{port}/docs/developer/quickstart")
    expect(output.index("/docs/developer/quickstart")).to be < output.index("DEV_SERVER_PORT=")
  end

  it "takes the port from PORT" do
    port = free_port.to_s

    expect(run_dev(env: { "PORT" => port }).first).to eq(port)
  end

  it "takes the port from .env over the shell, as foreman does" do
    port = free_port.to_s
    @dir.join(".env").write("SIGNUP_MODE=open\nPORT=\"#{port}\"\n")

    expect(run_dev(env: { "PORT" => free_port.to_s }).first).to eq(port)
  end

  it "takes the port from foreman's own -p and --port flags" do
    short, long = free_port.to_s, free_port.to_s

    expect(run_dev("-p", short).first).to eq(short)
    expect(run_dev("--port=#{long}").first).to eq(long)
  end

  it "opens DEV_OPEN_PATH in the background on the chosen port, without passing it to foreman" do
    port, foreman_args = run_dev(env: { "PORT" => free_port.to_s, "DEV_OPEN_PATH" => "/docs/developer/quickstart" })

    expect(@dir.join("opened").read).to match(%r{dev_open\.rb #{port} /docs/developer/quickstart$})
    expect(foreman_args).not_to include("/docs")
  end

  it "keeps the page opener out of foreman's children, so its exit can't stop the app" do
    output, = capture_dev(env: { "PORT" => free_port.to_s, "DEV_OPEN_PATH" => "/docs/developer/quickstart" })

    expect(output).not_to include("FOREMAN_CHILD_EXITED")
  end

  it "opens nothing without DEV_OPEN_PATH" do
    run_dev(env: { "PORT" => free_port.to_s })

    expect(@dir.join("opened")).not_to exist
  end
end
