# Public directory surface (2026-07 redesign): suppress the workspace shell —
# sidebar, identity bar, section-nav strip — on viewer-facing directory pages.
# Those are workspace-member chrome whose links (Overview, Settings) make no
# sense to someone browsing rooms/buildings; the directory renders full-width
# instead. The application layout reads @hide_workspace_chrome and falls back
# to its plain <main> branch. Tenancy (DirectoryScoped) is deliberately a
# separate concern: admin config screens are directory-scoped too but keep
# their workspace chrome.
module PublicDirectoryChrome
  extend ActiveSupport::Concern

  included do
    before_action { @hide_workspace_chrome = true }
  end
end
