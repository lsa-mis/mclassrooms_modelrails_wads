# Machine-Facing Entry Points

The template deliberately ships **no** machine-facing surface — no API
namespace, no webhook receiver, no MCP endpoint. Every entry point is a
cookie-mediated browser session, because that is where the tenancy invariant
is enforced: a controller resolves the workspace from the URL, sets
`Current.workspace`, and Pundit policies read it. This page is the map for
the day your fork adds its first non-browser entry point — which is exactly
the day that invariant is easiest to break.

## Why there is no machinery to reuse

A 2026-08-05 panel unanimously converted a proposed MCP seam from code to
this document: the MCP spec was still moving, unexercised code is a permanent
fork liability, and tool objects would sit outside
`spec/code_smells/no_unscoped_tenant_loads_spec.rb`'s controller-scoped
enforcement — code that *looks* guarded but isn't scanned. What a fork needs
is the pattern, not a dependency.

## The isolation boundary, reproduced outside a controller

In the request cycle, isolation is compositional: `WorkspaceScoped` resolves
`@workspace` from the slug, sets `Current.workspace`, and every query goes
through the association (`@workspace.projects.find_by!(...)`). `Tenanted`
installs **no** `default_scope`, so none of that is ambient — a job, rake
task, or tool handler gets `Current.workspace == nil` and an unscoped query
returns *every* tenant's rows.

Any non-controller call site must reproduce all three steps:

1. **Establish context explicitly, then read it back with the bang.**

   ```ruby
   Current.workspace = workspace_resolved_from_your_transport
   workspace = Current.workspace!   # raises if resolution failed — never nil-cascades
   ```

   `Current.workspace!` is the difference between "raises at the boundary"
   and "silently queries across tenants."

2. **Query through the workspace**, never through the class:
   `workspace.projects.find_by!(slug: ...)`, not `Project.find_by!(slug: ...)`.

3. **Authorize every action with Pundit**, passing the user your transport
   authenticated: `Pundit.authorize(user, record, :update?)`. There is no
   `verify_authorized` net outside controllers; the habit is the net.

See also §Cross-workspace queries in [Extending](extending) for the
sanctioned patterns when a job legitimately spans tenants.

## MCP specifically

Build the server **per request**, never as a process-global with ambient
state — an MCP process serving two tenants through one memoized context is
the cross-tenant bug. Carry the tenant in the server context and fetch it
with `fetch`, not `[]`:

```ruby
workspace_id = server_context.fetch(:workspace_id)  # missing tenant RAISES
Current.workspace = Current.user!.workspaces.kept.find(workspace_id)
```

`fetch` turns a mis-wired client into an exception instead of a nil that
some later query interprets as "all workspaces."

## The first shared secret (webhooks, API tokens)

- Prefer Rails' own machinery: `generates_token_for` (purpose-scoped,
  expiring, revocable by design) or `has_secure_token`.
- If you ever compare a raw secret, use
  `ActiveSupport::SecurityUtils.secure_compare(candidate, stored)` — never
  `==`, which leaks timing. This pattern lives here as documentation rather
  than as a helper because a standing pattern with zero call sites is
  decoration; add it with your first caller, next to its test.
- If the endpoint fetches URLs the caller supplies, read the outbound-request
  (SSRF) posture in [Security](security) **before** writing the fetch.

## Host/Origin posture for a second Rack service

The app boots with `config.hosts` pinned via `RAILS_HOST` and CSP configured
for the single web origin. A second exposed service (an MCP port, a webhook
listener on its own subdomain) needs the same treatment from day one: its
host added to `config.hosts`, TLS at the proxy, and — if browsers ever talk
to it — its origin considered in the CSP and cookie `SameSite` story. A
service reachable by IP that skips host authorization is the classic
DNS-rebinding foothold.

---

**Recorded triggers to revisit shipping actual MCP code in the template**
(kept honest on issue #558's history): a real fork runs an MCP endpoint in
production *and* the MCP spec goes two consecutive revisions without a
breaking change — or the template ships an authenticated API surface for
another reason, making MCP a genuinely thin seam.
