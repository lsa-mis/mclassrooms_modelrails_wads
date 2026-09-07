# frozen_string_literal: true

require "rails_helper"

# `Noticed::Deliverable#deliver` is `recipients ||= evaluate_recipients`
# (noticed-3.0.0, app/models/concerns/noticed/deliverable.rb:87). So an
# explicit recipient argument does not ADD to the notifier's `recipients`
# block — it REPLACES it, and the block never runs.
#
# For this app that block is not a convenience: it is where in-app delivery is
# gated. `permitted_in_app` (ApplicationNotifier) is the only thing standing
# between a dispatch and a `noticed_notifications` row, because Noticed v2
# auto-saves those rows and there is no `:database` delivery method left to
# hang a conditional on. It is also where the actor is dropped, so nobody is
# notified about their own action.
#
# Passing a recipient to a block-declaring notifier therefore delivers to
# someone who opted out, in quiet hours, or who is the actor — silently. No
# exception, no log line, nothing red. The inverse is just as quiet: a notifier
# with NO block, dispatched as `deliver(nil)`, resolves to zero recipients and
# writes no rows at all.
#
# Both directions held by hand when this spec was written; nothing enforced
# them. This does.
#
# Scanned shape: `SomeNotifier.with(...).deliver(...)` (line breaks anywhere
# in it are fine) in app/ outside
# app/notifiers. A dispatch assembled some other way (a bare `.deliver`, a
# notifier held in a local) is not seen — widen the pattern if that shape
# appears rather than working around it.
RSpec.describe "Code smell: notifier recipient dispatch matches its recipients block" do
  # Locals, not constants: a constant here lands on Object, where another spec
  # file's same-named constant clobbers it whenever CI shards both into one
  # worker.
  # `\s*` on both hops: a dispatch is routinely broken across lines
  # (`WorkspaceInvitationResentNotifier\n  .with(...)\n  .deliver(...)`), and a
  # pattern that only matched the one-line form skipped that site silently —
  # which a green guard would never have told anyone.
  dispatch_start = /(\w+Notifier)\s*\.with\s*\(/

  # A dispatch site is scanned wherever notifiers are fired from — never inside
  # app/notifiers itself, where `deliver` is defined and overridden.
  def dispatch_sources
    Dir[Rails.root.join("app/**/*.rb")].reject { _1.include?("/app/notifiers/") }
  end

  # Structural, not textual: Noticed's `recipients` DSL writes the block to the
  # `_recipients` class_attribute (noticed-3.0.0,
  # app/models/concerns/noticed/deliverable.rb), which is the same value
  # `deliver` reads. The old `/^\s*recipients\b/` source scan only approximated
  # it, and missed real declarations — `self.recipients do … end` reads as "no
  # block", and so does a subclass inheriting one, because the scan sees a
  # single file's text rather than the class. Both shapes would have been waved
  # through with an explicit recipient, skipping permitted_in_app silently.
  #
  # `constantize` deliberately, not `safe_constantize`: a notifier file that
  # does not define the class its name promises should fail loudly here rather
  # than drop out of the fence's coverage.
  def notifiers_declaring_recipients
    notifier_classes.select { |klass| klass._recipients.present? }.map(&:name)
  end

  def notifier_classes
    Dir[Rails.root.join("app/notifiers/*_notifier.rb")].filter_map do |file|
      next if File.basename(file) == "application_notifier.rb"
      File.basename(file, ".rb").camelize.constantize
    end
  end

  def all_notifiers
    notifier_classes.map(&:name)
  end

  # [notifier, deliver argument, "path:line"] for every dispatch in app/.
  def dispatch_sites(pattern)
    dispatch_sources.flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      source = without_comments(File.read(file))
      found = []
      position = 0

      while (match = pattern.match(source, position))
        position = match.end(0)
        after_with = balanced_end(source, match.end(0) - 1)
        next unless after_with

        tail = source[after_with..]
        deliver = tail.match(/\A\s*\.deliver\s*\(/)
        next unless deliver

        argument_end = balanced_end(tail, deliver.end(0) - 1)
        next unless argument_end

        found << [
          match[1],
          tail[deliver.end(0)...(argument_end - 1)].strip,
          "#{relative}:#{source[0...match.begin(0)].count("\n") + 1}"
        ]
      end

      found
    end
  end

  it "dispatches every notifier that declares a recipients block with deliver(nil)" do
    declaring = notifiers_declaring_recipients

    offenders = dispatch_sites(dispatch_start).filter_map do |notifier, argument, location|
      next unless declaring.include?(notifier)
      next if argument == "nil"

      "#{location}: #{notifier}...deliver(#{argument})"
    end

    expect(offenders).to be_empty,
      "Noticed's deliver is `recipients ||= evaluate_recipients`, so an explicit " \
      "recipient SKIPS the notifier's recipients block — and with it the " \
      "permitted_in_app preference gate and the actor exclusion. The delivery " \
      "still happens, to someone who may have opted out. Dispatch these with " \
      "deliver(nil):\n  #{offenders.join("\n  ")}"
  end

  it "dispatches every notifier without a recipients block to an explicit recipient" do
    declaring = notifiers_declaring_recipients

    offenders = dispatch_sites(dispatch_start).filter_map do |notifier, argument, location|
      next if declaring.include?(notifier)
      next unless argument.empty? || argument == "nil"

      "#{location}: #{notifier}...deliver(#{argument.presence || ''})"
    end

    expect(offenders).to be_empty,
      "This notifier declares no recipients block, so deliver(nil) resolves to " \
      "no recipients and writes no notification rows — a dispatch that silently " \
      "does nothing. Either name the recipient, or move recipient resolution " \
      "into a recipients block on the notifier:\n  #{offenders.join("\n  ")}"
  end

  it "resolves every dispatched notifier to a class under app/notifiers" do
    known = all_notifiers

    offenders = dispatch_sites(dispatch_start).filter_map do |notifier, _argument, location|
      "#{location}: #{notifier}" unless known.include?(notifier)
    end

    expect(offenders).to be_empty,
      "These dispatches name a notifier with no file under app/notifiers, so the " \
      "two checks above cannot tell whether it declares a recipients block and " \
      "skip it silently:\n  #{offenders.join("\n  ")}"
  end
end
