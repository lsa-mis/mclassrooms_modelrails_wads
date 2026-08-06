# Refuses to start a spec run into an already-locked test database.
#
# The single-host topology gives each test database one SQLite file, and
# config/database.yml installs a 5s Ruby-level busy handler (#304). That is the
# right call for the app, but it means two processes on the same test DB do not
# fail fast — they poison each other slowly. Every contended statement waits out
# the handler before raising, so the suite crawls and sheds failures across
# unrelated files, none of which name the cause. Observed in a fork on
# 2026-08-05: a 12-minute suite took 85 minutes and produced 30+ phantom
# failures before being killed.
#
# The kill is the second half of the trap. `pkill -f "bundle exec rspec"`
# matches the shell wrapper and orphans the `bin/rspec` child, which keeps the
# WAL lock — after which every run fails in the first `create(...)`.
#
# This lives in the boot path rather than in a dedicated runner script on
# purpose. The runner that caused the incident was a background task invoking
# `bundle exec rspec`; a guard you have to remember to invoke does not protect
# against someone who does not know to invoke it. Here it covers the plain
# runner, every parallel worker, agent invocations, and IDE runners alike.
require "shellwords"

module TestDatabaseLockGuard
  class ContendedDatabaseError < StandardError; end

  module_function

  # The file THIS process is about to open. Workers are safe from one another
  # because each gets its own file — but TEST_ENV_NUMBER is "" for worker 1, so
  # a parallel run and a plain `bundle exec rspec` genuinely do collide on
  # storage/test.sqlite3 (see the comment in config/database.yml).
  def database_path(env_number: ENV["TEST_ENV_NUMBER"])
    Rails.root.join("storage/test#{env_number}.sqlite3").to_s
  end

  def verify!(path = database_path)
    return unless lsof_available?

    pids = holder_pids(path)
    return if pids.empty?

    raise ContendedDatabaseError, <<~MESSAGE
      Another process is holding the test database:
        #{path}

      #{pids.map { |pid| "  PID #{pid}  #{describe_process(pid)}" }.join("\n")}

      Two runners on one SQLite test database do not fail fast — config/database.yml
      installs a 5s busy handler, so each contended statement waits it out. The suite
      will crawl and report failures in unrelated files that have nothing wrong with
      them.

      If that run is yours and still wanted, wait for it. Otherwise stop it by process
      GROUP, not by name:

        kill -- -$(ps -o pgid= #{pids.first} | tr -d ' ')

      `pkill -f "bundle exec rspec"` is what to avoid: it matches the shell wrapper and
      orphans the child, which keeps the lock. Confirm the file is free with:

        lsof #{path}*
    MESSAGE
  end

  # Excludes this process and anything sharing its process group — parallel
  # workers are forked from the runner and legitimately share the group.
  def holder_pids(path)
    own_group = Process.getpgrp
    raw_holder_pids(path).uniq.reject do |pid|
      pid == Process.pid || (Process.getpgid(pid) == own_group rescue false)
    end
  end

  def raw_holder_pids(path)
    # -t: terse (PIDs only). The WAL and shared-memory sidecars are held
    # separately from the main file, so a holder can appear on any of the three.
    out = `lsof -t #{Shellwords.escape(path)} #{Shellwords.escape("#{path}-wal")} #{Shellwords.escape("#{path}-shm")} 2>/dev/null`
    out.split("\n").filter_map { |line| Integer(line.strip, exception: false) }
  end

  def describe_process(pid)
    `ps -o command= -p #{pid.to_i} 2>/dev/null`.strip.presence || "(process details unavailable)"
  end

  def lsof_available?
    @lsof_available = system("command -v lsof > /dev/null 2>&1") if @lsof_available.nil?
    @lsof_available
  end
end

RSpec.configure do |config|
  # before(:suite) so it costs one lsof per process and fails before any example
  # has burned time waiting on the busy handler.
  config.before(:suite) { TestDatabaseLockGuard.verify! }
end
