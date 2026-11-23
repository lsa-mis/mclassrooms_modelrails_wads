# frozen_string_literal: true

require "socket"
require_relative "codespaces"

module DevPort
  class Busy < StandardError; end

  HOSTS = [ "127.0.0.1", "::1" ].freeze
  TRIES = 10
  QUICKSTART = "/docs/developer/quickstart"

  def self.busy?(port)
    HOSTS.any? do |host|
      Socket.tcp(host, port, connect_timeout: 0.2).close
      true
    rescue SystemCallError, SocketError, IOError
      false
    end
  end

  def self.choose(port, explicit:, container:)
    return port unless busy?(port)
    raise Busy, "Port #{port} is in use. Stop what's using it, or choose another: bin/dev -p #{port + 1}" if explicit || container

    (port + 1..port + TRIES).find { |candidate| !busy?(candidate) } ||
      raise(Busy, "Ports #{port} to #{port + TRIES} are all in use. Choose a free one: bin/dev -p PORT")
  end

  def self.container?(env = ENV, dockerenv: File.exist?("/.dockerenv"))
    Codespaces.active?(env) || env["REMOTE_CONTAINERS"] == "true" || dockerenv
  end

  def self.url(port, env = ENV)
    Codespaces.active?(env) ? "https://#{Codespaces.forwarded_host(port:, env:)}" : "http://localhost:#{port}"
  end

  def self.announcement(port, env = ENV)
    "App: #{url(port, env)}   Start here: #{url(port, env)}#{QUICKSTART}"
  end
end

if $PROGRAM_NAME == __FILE__
  command, port, origin = ARGV
  case command
  when "choose"
    begin
      puts DevPort.choose(Integer(port), explicit: origin == "explicit", container: DevPort.container?)
    rescue DevPort::Busy => e
      warn e.message
      exit 1
    end
  when "announce"
    puts DevPort.announcement(Integer(port))
  end
end
