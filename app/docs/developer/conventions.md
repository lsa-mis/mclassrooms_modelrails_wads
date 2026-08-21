---
title: Code Conventions
description: Where information about the code should live — self-documenting code, PR bodies, docs, and the narrow case for inline comments
keywords: comments commenting conventions documentation hierarchy self-documenting pull request why rationale
---

<!-- synced-from: modelrails_playbook/standards/global/commenting.md@2026-08-20 -->

# Code Conventions

This page covers one convention that shapes every change in this codebase:
**where information about the code should live**. Three places, in order of
preference. Most code needs only the first.

## 1. Self-documenting code first

Structure and naming carry the *what*. A method named for its domain intent
(`Workspace#admit`, `Invitation.bulk_invite!`), a variable named for its
contents, a guard clause that reads as the rule it enforces — these make a
comment describing the same thing redundant the moment it's written, and
wrong the first time the code changes without it.

If you're about to write a comment explaining what the next few lines do,
try renaming or extracting first. The comment you no longer need is the
better outcome.

## 2. The *why* lives in PR bodies and developer docs

Rationale — why this approach, what else was tried, what trade-off was
accepted — belongs where it was decided: the pull request that made the
change, and these developer docs when the reasoning is load-bearing for
future work. Both are searchable, both survive refactors, and neither goes
stale sitting next to code it no longer describes.

Practically: write the PR body as if the next person will read it *instead
of* asking you. When a decision will matter beyond one PR, promote it to the
relevant page under `/docs/developer`.

## 3. Inline comments: only what code cannot express

A comment earns its place when it states a constraint the code itself can't
show. Three shapes qualify:

- **Cross-file invariants** — "this must stay in sync with X", "this is the
  single home of Y, previously duplicated and drifting."
- **Platform or library semantics** — behavior of Rails, SQLite, a gem, or
  a browser that the call site can't make visible.
- **Traps for a correct-looking instinct** — where the obvious "fix" is
  wrong, and the comment stops the next developer from making it.

The form is a **one-line gist plus a pointer** to the PR, doc, or issue
carrying the full story. If the explanation is growing into an essay, the
essay belongs in a doc page (rule 2) with the gist-and-pointer left behind.

### The test a comment must pass

> A comment survives review only if it states a constraint the code itself
> can't show — never where the change came from, what the next line does,
> or why the change is correct.

Provenance ("added in PR #123"), narration ("increment the counter"), and
self-justification all fail the test: git history, the code, and the PR body
already carry them.

## Comments are evergreen

Never write comments about recent changes or fixes ("now handles the new
flow", "temporary until the migration lands"). A comment should read as true
in five years or not be written. Time-bound context goes in the PR body.

## Scope: rules apply forward

These rules govern code you write or substantially change. Existing code is
brought into line when it's next touched — not swept. When a repo-wide sweep
is genuinely wanted, it's undertaken deliberately and by name (this repo's
comment audit was one; its deliberate keep-decisions are recorded in the
PRs that made them).

A longer comment that passes the test can survive — a header documenting a
claim-exception matrix that lives in one place precisely because it used to
drift across two, for example. The bar isn't length; it's whether the code
could say it instead.
