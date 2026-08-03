<!-- Keep this short. Delete any section that doesn't apply. -->

## What & why

<!-- One or two sentences: what this changes and the problem it solves. Link issues with #123. -->

## How it was tested

<!-- The commands you ran and their result. The full RSpec suite must be green before merge. -->

- [ ] Full test suite green (Lefthook pre-push ran the suite locally)
- [ ] New behavior is covered by specs, written failing-first (TDD)

## Checklist

- [ ] All user-facing text uses I18n locale keys (no hardcoded strings)
- [ ] Controllers enforce Pundit authorization where the action is policy-scoped
- [ ] RESTful routes only (no custom aliases, no single-action sub-resource controllers)
- [ ] **Docs:** if you changed behavior, the relevant `app/docs/*` page is updated — and if you touched **auth, onboarding, invitations, or clientside** flows, re-check the Application Flows guide (`app/docs/user/application-flows.md`)
- [ ] **Changelog:** user-visible or operational changes get an entry in `CHANGELOG.mclassrooms.md` under `[Unreleased]`, in this PR. (Root `CHANGELOG.md` is the upstream template's — it arrives via sync, so fork entries there become merge conflicts.)

## UI changes only

<!-- Delete this whole section for non-UI PRs. -->

- [ ] Built on a documented `UI::*` primitive / canonical design-system class (no raw hex, off-system fonts, or `focus:ring-*`)
- [ ] Verified in **both** light and dark themes (AAA contrast is proven in CI, not locally)
- [ ] Screenshots attached below (both themes)

<!-- Screenshots: -->
