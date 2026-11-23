# frozen_string_literal: true

require "socket"

module FreePort
  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1].tap { server.close }
  end
end

RSpec.configure do |config|
  config.include FreePort
end
