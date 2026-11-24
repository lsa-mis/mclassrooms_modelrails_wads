# frozen_string_literal: true

require "rbconfig"
require_relative "dev_port"

module DevOpen
  def self.call(port:, path:, env: ENV, host_os: RbConfig::CONFIG["host_os"], container: DevPort.container?(env),
                opener: ->(cmd, url) { system(cmd, url) }, wait: 60, tick: 0.5, out: $stdout)
    url = "#{DevPort.url(port, env)}#{path}"
    return finish(:timed_out, url, out) unless answered?(port, wait, tick)

    command = opener_command(env, host_os) unless container
    return finish(:printed, url, out) unless command && opener.call(command, url)

    :opened
  end

  def self.opener_command(env, host_os)
    return "open" if host_os.include?("darwin")
    return unless env["DISPLAY"] || env["WAYLAND_DISPLAY"]

    "xdg-open" if env.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "xdg-open")) }
  end

  def self.answered?(port, wait, tick)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
    until DevPort.busy?(port)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep tick
    end
    true
  end

  def self.finish(result, url, out)
    out.puts "Open: #{url}"
    result
  end
end

DevOpen.call(port: Integer(ARGV[0]), path: ARGV[1]) if $PROGRAM_NAME == __FILE__
