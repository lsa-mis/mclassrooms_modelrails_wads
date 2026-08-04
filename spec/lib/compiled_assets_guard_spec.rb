require "rails_helper"

# Guards the gap that produced 132 opaque system-spec failures on 2026-08-01:
# tailwindcss-rails enhances `assets:clobber` with `tailwindcss:clobber`, so
# `bin/setup` deletes the compiled stylesheet, and no local RSpec path rebuilds
# it (the gem's `test:prepare` enhancement is the Minitest path — RSpec never
# invokes it). Without CSS every axe-contrast and layout-dependent interaction
# spec fails for reasons that look nothing like a missing asset.
RSpec.describe CompiledAssetsGuard do
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:stylesheet) { workdir.join("tailwind.css") }

  after { FileUtils.remove_entry(workdir) }

  describe ".verify!" do
    it "passes silently when the stylesheet exists with content" do
      stylesheet.write(".btn{color:red}")

      expect { described_class.verify!(stylesheet) }.not_to raise_error
    end

    it "raises when the stylesheet is absent" do
      expect { described_class.verify!(stylesheet) }
        .to raise_error(described_class::MissingCompiledAssetsError)
    end

    # A clobber can leave a zero-byte file behind, which passes an exist? check
    # but renders every page unstyled exactly as a missing file would.
    it "raises when the stylesheet exists but is empty" do
      stylesheet.write("")

      expect { described_class.verify!(stylesheet) }
        .to raise_error(described_class::MissingCompiledAssetsError)
    end

    it "names the build command so the failure is self-resolving" do
      expect { described_class.verify!(stylesheet) }
        .to raise_error(/bin\/rails tailwindcss:build/)
    end

    it "names the missing path so the failure is diagnosable" do
      expect { described_class.verify!(stylesheet) }
        .to raise_error(/#{Regexp.escape(stylesheet.to_s)}/)
    end
  end

  describe "the real suite's stylesheet" do
    # Belt-and-braces: if this fails, the guard wired into system specs is
    # about to fire for every one of them.
    it "is present and non-empty for this run" do
      expect { described_class.verify! }.not_to raise_error
    end
  end
end
