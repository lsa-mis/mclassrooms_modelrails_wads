class User < ApplicationRecord
  # The new-device sign-in detector's memory: a bounded list of (browser, OS)
  # fingerprints this user has signed in from.
  module KnownDevices
    extend ActiveSupport::Concern

    MAX_KNOWN_BROWSERS = 20

    class_methods do
      # Version-stripped on purpose (a browser update is not a new device);
      # SignInFromNewDeviceNotifier's dedup key reuses this exact formula.
      def browser_digest(user_agent, os)
        Digest::SHA256.hexdigest("#{user_agent.to_s.gsub(/[\d_.]+/, "")} #{os}")
      end
    end

    def seen_browser?(user_agent, os)
      digest = self.class.browser_digest(user_agent, os)
      last_known_browsers.any? { |entry| entry["digest"] == digest }
    end

    def record_browser!(user_agent, os)
      digest = self.class.browser_digest(user_agent, os)
      now = Time.current
      browsers = last_known_browsers.dup
      if (entry = browsers.find { |e| e["digest"] == digest })
        entry["last_seen_at"] = now.iso8601
      else
        browsers << {
          "digest" => digest,
          "first_seen_at" => now.iso8601,
          "last_seen_at" => now.iso8601
        }
        # Bounded: this JSON column is read and rewritten on the sign-in hot
        # path (SQLite single writer), so it must not grow with UA churn.
        if browsers.size > MAX_KNOWN_BROWSERS
          browsers = browsers.sort_by { |e| e["last_seen_at"] }.last(MAX_KNOWN_BROWSERS)
        end
      end
      update_column(:last_known_browsers, browsers)
    end
  end
end
