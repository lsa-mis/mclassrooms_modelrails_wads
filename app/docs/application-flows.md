---
title: Application Flows
description: A builder's guide to the app's core journeys for developers and designers extending the template — clean wireframes paired with full-size prose explaining the why (the framework decision, seam, or guarantee) behind each screen, on a domain-model primer.
keywords: wireframes flows builder guide developers designers why rationale model workspace membership role project tools clientside onboarding seam readable
---

# Application Flows

For **developers and designers extending this template**. Each flow shows the screens as a wireframe; the **"Why"** beneath it — rendered as normal, readable prose — explains the framework decision, the seam you'd extend, or the guarantee it gives you. The end-user flows are intentionally tight, so this page is for *builders*, not users. For the full detail behind each journey, follow the per-flow links to [Email & verification](/docs/emails), [Onboarding](/docs/onboarding), [Project tools](/docs/project-tools), [Workspaces](/docs/workspaces), and [Clientside](/docs/clientside).

## The model behind every flow

Five concepts the flows plug into — knowing these is usually enough to avoid fighting the template.

| Concept | What it is | Why it's shaped this way |
| --- | --- | --- |
| `User` | One identity / login | Reused across workspaces — one person, many memberships. |
| `Workspace` | The tenant | Top-level boundary; `Current.workspace` scopes data via the `Tenanted` concern. |
| `Membership` + `Role` | owner · admin · member · viewer | Role is **per-workspace, not global** (JSON permissions); Pundit authorizes. |
| `Project` + tools | Belongs to a workspace | Enabled tools are a **registry** (`enabled_tools` JSON) — extend in an initializer, no view edits. |
| `ClientAccess` | External client ↔ project | A **separate access axis**, not a membership: no seat, never in workspace policies. |

## 1 · Sign up & sign in

<svg viewBox="0 0 600 410" width="100%" role="img" aria-label="Sign up and sign in, three screens. Screen A, Sign in or sign up, with an Email address field, a Continue button, a Sign in with a passkey button, and a caption or use a magic link. An arrow labelled continue leads to screen B, Check your email, which says a sign-in link was sent to jane@acme.com, with a Resend link button. After clicking the link, a connector drops to screen C, Set up a passkey?, which offers Add a passkey for faster sign-in with Add a passkey and Not now buttons." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-g1" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="20" width="270" height="178" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="44" x2="290" y2="44" stroke-width="1"/>
  <circle cx="34" cy="32" r="3" stroke-width="1"/><circle cx="46" cy="32" r="3" stroke-width="1"/><circle cx="58" cy="32" r="3" stroke-width="1"/>
  <rect x="74" y="26" width="206" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="40" y="70" font-size="13" font-weight="700" fill="currentColor" stroke="none">Sign in or sign up</text>
  <text x="40" y="92" font-size="10" fill="currentColor" stroke="none" opacity="0.7">Email address</text>
  <rect x="40" y="97" width="220" height="19" rx="4" stroke-width="1"/><text x="48" y="110" font-size="10.5" fill="currentColor" stroke="none" opacity="0.45">jane@acme.com</text>
  <rect class="text-accent" x="40" y="124" width="220" height="22" rx="6" stroke-width="2.25"/><text class="text-accent" x="150" y="139" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <rect x="40" y="152" width="220" height="22" rx="6" stroke-width="1.25" opacity="0.8"/><text x="150" y="167" text-anchor="middle" font-size="10.5" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Sign in with a passkey</text>
  <text x="150" y="189" text-anchor="middle" font-size="9.5" fill="currentColor" stroke="none" opacity="0.55">or use a magic link</text>
  <rect x="310" y="20" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="310" y1="44" x2="580" y2="44" stroke-width="1"/>
  <circle cx="324" cy="32" r="3" stroke-width="1"/><circle cx="336" cy="32" r="3" stroke-width="1"/><circle cx="348" cy="32" r="3" stroke-width="1"/>
  <rect x="364" y="26" width="206" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="330" y="72" font-size="13" font-weight="700" fill="currentColor" stroke="none">Check your email</text>
  <text x="330" y="96" font-size="10.5" fill="currentColor" stroke="none" opacity="0.65">We sent a sign-in link to</text>
  <text x="330" y="112" font-size="10.5" fill="currentColor" stroke="none" opacity="0.65">jane@acme.com — click it to continue.</text>
  <rect x="330" y="128" width="115" height="22" rx="6" stroke-width="1.25" opacity="0.8"/><text x="387" y="143" text-anchor="middle" font-size="10.5" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Resend link</text>
  <rect x="20" y="240" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="264" x2="290" y2="264" stroke-width="1"/>
  <circle cx="34" cy="252" r="3" stroke-width="1"/><circle cx="46" cy="252" r="3" stroke-width="1"/><circle cx="58" cy="252" r="3" stroke-width="1"/>
  <rect x="74" y="246" width="206" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="40" y="292" font-size="13" font-weight="700" fill="currentColor" stroke="none">Set up a passkey?</text>
  <text x="40" y="316" font-size="10.5" fill="currentColor" stroke="none" opacity="0.65">Add a passkey for faster sign-in.</text>
  <rect class="text-accent" x="40" y="330" width="130" height="22" rx="6" stroke-width="2.25"/><text class="text-accent" x="105" y="345" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">Add a passkey</text>
  <rect x="180" y="330" width="80" height="22" rx="6" stroke-width="1.25" opacity="0.8"/><text x="220" y="345" text-anchor="middle" font-size="10.5" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Not now</text>
  <path d="M290 109 H308" stroke-width="1.5" marker-end="url(#flowarrow-g1)"/><text x="299" y="102" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.6">continue</text>
  <path d="M445 170 V215 H155 V238" stroke-width="1.5" opacity="0.6" marker-end="url(#flowarrow-g1)"/><text x="300" y="210" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.6">after the link signs you in</text>
</svg>

<details>
<summary>Why it's shaped this way</summary>

- **Sign in or sign up** — One email-first door (`sessions#new` → `lookup`) for both. A new email gets a magic-link registration; an existing one gets a magic-link sign-in. There is **no password at signup** — password is a settings-only opt-in. A returning user with a passkey can tap **Sign in with a passkey** (usernameless/discoverable); any failure falls back to the magic link, so no one is stranded.
- **Check your email** — The magic link proves email ownership: clicking it verifies the address **and** signs the user in in one step. "Forgot password?" reuses this same link (a `set_password`-intent magic link) — there is no separate reset flow.
- **Set up a passkey?** — A one-time, dismissible prompt after the first sign-in (only when the user has no passkey yet and the browser supports WebAuthn). Adding one makes the next sign-in a single tap; magic link remains the universal fallback. Manage passkeys anytime in Settings.
</details>

## 2 · First-run onboarding

<svg viewBox="0 0 600 410" width="100%" role="img" aria-label="First-run onboarding, four steps. Step 1 Name your workspace (field Workspace name, Continue). Step 2 Create first project (field Project name, Continue). A connector first project saved drops to step 3 Pick your tools (Docs and Files checked, Save tools). Step 4 Invite your team (Email addresses, Send invites)." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-g2" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="20" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="44" x2="290" y2="44" stroke-width="1"/>
  <circle cx="40" cy="32" r="3" stroke-width="1"/><circle cx="52" cy="32" r="3" stroke-width="1"/><circle cx="64" cy="32" r="3" stroke-width="1"/>
  <rect x="80" y="26" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="40" y="72" font-size="12.5" font-weight="700" fill="currentColor" stroke="none">Name your workspace</text>
  <text x="40" y="94" font-size="9.5" fill="currentColor" stroke="none" opacity="0.7">Workspace name</text>
  <rect x="40" y="99" width="220" height="18" rx="4" stroke-width="1"/><text x="48" y="111.5" font-size="10" fill="currentColor" stroke="none" opacity="0.45">Acme Co</text>
  <rect class="text-accent" x="40" y="132" width="120" height="21" rx="6" stroke-width="2.25"/><text class="text-accent" x="100" y="146.5" text-anchor="middle" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <circle cx="20" cy="20" r="11" stroke-width="1.5"/><text x="20" y="24" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">1</text>
  <rect x="310" y="20" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="310" y1="44" x2="580" y2="44" stroke-width="1"/>
  <circle cx="330" cy="32" r="3" stroke-width="1"/><circle cx="342" cy="32" r="3" stroke-width="1"/><circle cx="354" cy="32" r="3" stroke-width="1"/>
  <rect x="370" y="26" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="330" y="72" font-size="12.5" font-weight="700" fill="currentColor" stroke="none">Create first project</text>
  <text x="330" y="94" font-size="9.5" fill="currentColor" stroke="none" opacity="0.7">Project name</text>
  <rect x="330" y="99" width="220" height="18" rx="4" stroke-width="1"/><text x="338" y="111.5" font-size="10" fill="currentColor" stroke="none" opacity="0.45">Acme Website</text>
  <rect class="text-accent" x="330" y="132" width="120" height="21" rx="6" stroke-width="2.25"/><text class="text-accent" x="390" y="146.5" text-anchor="middle" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <circle cx="310" cy="20" r="11" stroke-width="1.5"/><text x="310" y="24" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">2</text>
  <rect x="20" y="210" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="234" x2="290" y2="234" stroke-width="1"/>
  <circle cx="40" cy="222" r="3" stroke-width="1"/><circle cx="52" cy="222" r="3" stroke-width="1"/><circle cx="64" cy="222" r="3" stroke-width="1"/>
  <rect x="80" y="216" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="40" y="262" font-size="12.5" font-weight="700" fill="currentColor" stroke="none">Pick your tools</text>
  <rect class="text-accent" x="40" y="278" width="13" height="13" rx="3" stroke-width="1.25"/><path class="text-accent" d="M43,285 L45.5,288 L50,282" stroke-width="1.75"/>
  <text x="60" y="289" font-size="10.5" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <rect class="text-accent" x="40" y="320" width="120" height="21" rx="6" stroke-width="2.25"/><text class="text-accent" x="100" y="334.5" text-anchor="middle" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Save tools</text>
  <circle cx="20" cy="210" r="11" stroke-width="1.5"/><text x="20" y="214" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">3</text>
  <rect x="310" y="210" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="310" y1="234" x2="580" y2="234" stroke-width="1"/>
  <circle cx="330" cy="222" r="3" stroke-width="1"/><circle cx="342" cy="222" r="3" stroke-width="1"/><circle cx="354" cy="222" r="3" stroke-width="1"/>
  <rect x="370" y="216" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="330" y="262" font-size="12.5" font-weight="700" fill="currentColor" stroke="none">Invite your team</text>
  <text x="330" y="284" font-size="9.5" fill="currentColor" stroke="none" opacity="0.7">Email addresses</text>
  <rect x="330" y="289" width="220" height="18" rx="4" stroke-width="1"/><text x="338" y="301.5" font-size="9.5" fill="currentColor" stroke="none" opacity="0.45">sam@example.com, lee@example.com</text>
  <rect class="text-accent" x="330" y="322" width="130" height="21" rx="6" stroke-width="2.25"/><text class="text-accent" x="395" y="336.5" text-anchor="middle" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Send invites</text>
  <circle cx="310" cy="210" r="11" stroke-width="1.5"/><text x="310" y="214" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">4</text>
  <path d="M290 95 H308" stroke-width="1.5" marker-end="url(#flowarrow-g2)"/><text x="299" y="88" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.6">next</text>
  <path d="M445 170 V190 H155 V208" stroke-width="1.5" opacity="0.6" marker-end="url(#flowarrow-g2)"/><text x="300" y="185" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.6">first project saved</text>
  <path d="M290 285 H308" stroke-width="1.5" marker-end="url(#flowarrow-g2)"/><text x="299" y="278" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.6">next</text>
</svg>

<details>
<summary>Why it's shaped this way</summary>

- **Name your workspace** — Onboarding only runs under `WORKSPACE_ON_SIGNUP=none`; the `RequiresOnboarding` guard is posture-gated and html-only, returning early in every other posture.
- **Create your first project** — Derive-from-data: `onboarded_at` is the only marker, and the current step is computed from what already exists — so the wizard is resumable with no per-step flags to keep in sync.
- **Pick your tools** — Self-hides unless more than one tool is registered (never a one-option screen). It's a forward-only interstitial, not a resume step. Register tools in `config/initializers/project_tools.rb`.
- **Invite your team** — Optional: skipping still lands a fully working project; finishing stamps `onboarded_at`. The project home's tabs follow the project's `enabled_tools`.
</details>

## 3 · Project home & tools

<svg viewBox="0 0 600 180" width="100%" role="img" aria-label="Project home and tools, two screens. The project home for Acme Website with an active Docs and Files tab and a Project tools settings entry. An arrow labelled settings leads to Project tools settings, with a checked Docs and Files option described as Documents and files for this project, and a Save tools button." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-g3" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="20" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="44" x2="290" y2="44" stroke-width="1"/>
  <circle cx="34" cy="32" r="3" stroke-width="1"/><circle cx="46" cy="32" r="3" stroke-width="1"/><circle cx="58" cy="32" r="3" stroke-width="1"/>
  <rect x="74" y="26" width="206" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="40" y="68" font-size="9" fill="currentColor" stroke="none" opacity="0.5">Acme Co</text>
  <text x="40" y="86" font-size="13" font-weight="700" fill="currentColor" stroke="none">Acme Website</text>
  <rect class="text-accent" x="40" y="96" width="92" height="17" rx="5" stroke-width="2"/><text class="text-accent" x="86" y="108" text-anchor="middle" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <text x="142" y="108" font-size="9.5" fill="currentColor" stroke="none" opacity="0.55">Project tools</text>
  <rect x="40" y="126" width="220" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="40" y="139" width="180" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="40" y="152" width="200" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="310" y="20" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="310" y1="44" x2="580" y2="44" stroke-width="1"/>
  <circle cx="324" cy="32" r="3" stroke-width="1"/><circle cx="336" cy="32" r="3" stroke-width="1"/><circle cx="348" cy="32" r="3" stroke-width="1"/>
  <rect x="364" y="26" width="206" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="330" y="70" font-size="13" font-weight="700" fill="currentColor" stroke="none">Project tools</text>
  <text x="330" y="90" font-size="9.5" fill="currentColor" stroke="none" opacity="0.6">Choose which tools this project uses.</text>
  <rect class="text-accent" x="330" y="100" width="13" height="13" rx="3" stroke-width="1.25"/><path class="text-accent" d="M333,107 L335.5,110 L340,104" stroke-width="1.75"/>
  <text x="350" y="111" font-size="10.5" fill="currentColor" stroke="none">Docs &amp; Files</text>
  <text x="350" y="126" font-size="9" fill="currentColor" stroke="none" opacity="0.5">Documents and files for this project.</text>
  <rect class="text-accent" x="330" y="140" width="110" height="21" rx="6" stroke-width="2.25"/><text class="text-accent" x="385" y="154.5" text-anchor="middle" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Save tools</text>
  <path d="M290 100 H308" stroke-width="1.5" marker-end="url(#flowarrow-g3)"/>
</svg>

<details>
<summary>Why it's shaped this way</summary>

- **Project home** — The tab bar is driven by the project's `enabled_tools` (JSON), not a hardcoded list — so a fork can add a tool without touching this view.
- **Project tools (settings)** — Toggling writes `enabled_tools`. Register tools in `config/initializers/project_tools.rb`; gate a tool's controller with the `EnforcesProjectTool` concern. The base template ships only **Docs & Files**.
</details>

## 4 · Invite teammates

<svg viewBox="0 0 790 180" width="100%" role="img" aria-label="Inviting teammates, three screens. Invite members, an Email addresses field with a Member role and Send invitations. A dashed arrow labelled sent leads to the invitation email, Jamie invited you to join Acme Co as a Member, with Accept invitation and Decline. An arrow labelled accept leads to Set up your login, with First name and Last name and a Join button." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-g4" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="20" width="230" height="150" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="44" x2="250" y2="44" stroke-width="1"/>
  <circle cx="34" cy="32" r="3" stroke-width="1"/><circle cx="46" cy="32" r="3" stroke-width="1"/><circle cx="58" cy="32" r="3" stroke-width="1"/>
  <rect x="74" y="26" width="166" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="38" y="70" font-size="12" font-weight="700" fill="currentColor" stroke="none">Invite members</text>
  <text x="38" y="90" font-size="9" fill="currentColor" stroke="none" opacity="0.7">Email addresses</text>
  <rect x="38" y="95" width="192" height="17" rx="4" stroke-width="1"/><text x="45" y="107" font-size="9" fill="currentColor" stroke="none" opacity="0.45">sam@acme.com, lee@acme.com</text>
  <rect x="38" y="120" width="64" height="15" rx="4" stroke-width="1" opacity="0.7"/><text x="70" y="131" text-anchor="middle" font-size="9" fill="currentColor" stroke="none" opacity="0.8">Member ▾</text>
  <rect class="text-accent" x="38" y="142" width="130" height="20" rx="6" stroke-width="2.25"/><text class="text-accent" x="103" y="155.5" text-anchor="middle" font-size="10" font-weight="700" fill="currentColor" stroke="none">Send invitations</text>
  <rect x="280" y="20" width="230" height="150" rx="11" stroke-width="1.5"/>
  <line x1="280" y1="44" x2="510" y2="44" stroke-width="1"/>
  <circle cx="294" cy="32" r="3" stroke-width="1"/><circle cx="306" cy="32" r="3" stroke-width="1"/><circle cx="318" cy="32" r="3" stroke-width="1"/>
  <rect x="334" y="26" width="166" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="298" y="70" font-size="12" font-weight="700" fill="currentColor" stroke="none">You've been invited</text>
  <text x="298" y="90" font-size="9.5" fill="currentColor" stroke="none" opacity="0.65">Jamie invited you to join Acme</text>
  <text x="298" y="103" font-size="9.5" fill="currentColor" stroke="none" opacity="0.65">Co as a Member.</text>
  <rect class="text-accent" x="298" y="115" width="140" height="20" rx="6" stroke-width="2.25"/><text class="text-accent" x="368" y="128.5" text-anchor="middle" font-size="10" font-weight="700" fill="currentColor" stroke="none">Accept invitation</text>
  <rect x="298" y="142" width="80" height="17" rx="5" stroke-width="1.25" opacity="0.8"/><text x="338" y="153.5" text-anchor="middle" font-size="9" font-weight="600" fill="currentColor" stroke="none" opacity="0.75">Decline</text>
  <rect x="540" y="20" width="230" height="150" rx="11" stroke-width="1.5"/>
  <line x1="540" y1="44" x2="770" y2="44" stroke-width="1"/>
  <circle cx="554" cy="32" r="3" stroke-width="1"/><circle cx="566" cy="32" r="3" stroke-width="1"/><circle cx="578" cy="32" r="3" stroke-width="1"/>
  <rect x="594" y="26" width="166" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="558" y="68" font-size="12" font-weight="700" fill="currentColor" stroke="none">Set up your login</text>
  <text x="558" y="86" font-size="9" fill="currentColor" stroke="none" opacity="0.7">First name</text>
  <rect x="558" y="91" width="192" height="16" rx="4" stroke-width="1"/><text x="565" y="102.5" font-size="9.5" fill="currentColor" stroke="none" opacity="0.45">Sam</text>
  <text x="558" y="122" font-size="9" fill="currentColor" stroke="none" opacity="0.7">Last name</text>
  <rect x="558" y="127" width="192" height="16" rx="4" stroke-width="1"/><text x="565" y="138.5" font-size="9.5" fill="currentColor" stroke="none" opacity="0.45">Diaz</text>
  <rect class="text-accent" x="558" y="148" width="120" height="16" rx="5" stroke-width="2.25"/><text class="text-accent" x="618" y="159" text-anchor="middle" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Join Acme Co</text>
  <path d="M250 95 H278" stroke-width="1.5" stroke-dasharray="6 4" opacity="0.6" marker-end="url(#flowarrow-g4)"/><text x="264" y="88" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.6">sent</text>
  <path d="M510 95 H538" stroke-width="1.5" marker-end="url(#flowarrow-g4)"/>
</svg>

<details>
<summary>Why it's shaped this way</summary>

- **Invite members** — Role is set at invite time and is per-workspace (JSON permissions); only `manage_members` users can invite (Pundit). A shareable magic link is the alternative for open joining.
- **Invitation email** — The invite carries the recipient's email, so the bearer link isn't a free-for-all.
- **Accept / set up login** — Consume-before-verify with an `EmailMismatch` guard: a leaked link can't be claimed by a different address. Existing users join in one click; a new email finishes a **passwordless** signup (name only — magic link already proved the email). One `User`, reused everywhere after.
</details>

## 5 · Clientside

<svg viewBox="0 0 600 410" width="100%" role="img" aria-label="Clientside, four steps. Step 1 Client access, a toggle Turn on Clientside and Save. Step 2 Edit document, a checked Share with the client side. Step 3 Invite a client, Client email and Their company and Send client invite. Step 4 the accent-highlighted client area, Acme Co Client area, Shared with you, read-only items." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs><marker id="flowarrow-g5" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/></marker></defs>
  <rect x="20" y="20" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="44" x2="290" y2="44" stroke-width="1"/>
  <circle cx="40" cy="32" r="3" stroke-width="1"/><circle cx="52" cy="32" r="3" stroke-width="1"/><circle cx="64" cy="32" r="3" stroke-width="1"/>
  <rect x="80" y="26" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="40" y="72" font-size="12.5" font-weight="700" fill="currentColor" stroke="none">Client access</text>
  <rect class="text-accent" x="40" y="90" width="30" height="15" rx="7.5" stroke-width="1.25"/><circle class="text-accent" cx="63" cy="97.5" r="5" fill="currentColor" stroke="none"/>
  <text x="78" y="101" font-size="10" fill="currentColor" stroke="none">Turn on Clientside</text>
  <rect class="text-accent" x="40" y="128" width="80" height="21" rx="6" stroke-width="2.25"/><text class="text-accent" x="80" y="142.5" text-anchor="middle" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Save</text>
  <circle cx="20" cy="20" r="11" stroke-width="1.5"/><text x="20" y="24" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">1</text>
  <rect x="310" y="20" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="310" y1="44" x2="580" y2="44" stroke-width="1"/>
  <circle cx="330" cy="32" r="3" stroke-width="1"/><circle cx="342" cy="32" r="3" stroke-width="1"/><circle cx="354" cy="32" r="3" stroke-width="1"/>
  <rect x="370" y="26" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="330" y="72" font-size="12.5" font-weight="700" fill="currentColor" stroke="none">Edit document</text>
  <rect class="text-accent" x="330" y="88" width="13" height="13" rx="3" stroke-width="1.25"/><path class="text-accent" d="M333,95 L335.5,98 L340,92" stroke-width="1.75"/>
  <text x="350" y="99" font-size="10.5" fill="currentColor" stroke="none">Share with the client side</text>
  <text x="350" y="114" font-size="9" fill="currentColor" stroke="none" opacity="0.5">shown only when Clientside is on</text>
  <rect class="text-accent" x="330" y="128" width="80" height="21" rx="6" stroke-width="2.25"/><text class="text-accent" x="370" y="142.5" text-anchor="middle" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Save</text>
  <circle cx="310" cy="20" r="11" stroke-width="1.5"/><text x="310" y="24" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">2</text>
  <rect x="20" y="210" width="270" height="150" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="234" x2="290" y2="234" stroke-width="1"/>
  <circle cx="40" cy="222" r="3" stroke-width="1"/><circle cx="52" cy="222" r="3" stroke-width="1"/><circle cx="64" cy="222" r="3" stroke-width="1"/>
  <rect x="80" y="216" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="40" y="262" font-size="12.5" font-weight="700" fill="currentColor" stroke="none">Invite a client</text>
  <text x="40" y="284" font-size="9" fill="currentColor" stroke="none" opacity="0.7">Client email</text>
  <rect x="40" y="289" width="220" height="17" rx="4" stroke-width="1"/><text x="48" y="301" font-size="9.5" fill="currentColor" stroke="none" opacity="0.45">dana@bigco.com</text>
  <text x="40" y="320" font-size="9" fill="currentColor" stroke="none" opacity="0.7">Their company</text>
  <rect x="40" y="325" width="220" height="15" rx="4" stroke-width="1"/><text x="48" y="336" font-size="9.5" fill="currentColor" stroke="none" opacity="0.45">BigCo</text>
  <rect class="text-accent" x="40" y="344" width="140" height="13" rx="5" stroke-width="2.25"/><text class="text-accent" x="110" y="353.5" text-anchor="middle" font-size="9.5" font-weight="700" fill="currentColor" stroke="none">Send client invite</text>
  <circle cx="20" cy="210" r="11" stroke-width="1.5"/><text x="20" y="214" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">3</text>
  <rect class="text-accent" x="310" y="210" width="270" height="150" rx="11" stroke-width="2"/>
  <line x1="310" y1="234" x2="580" y2="234" stroke-width="1"/>
  <circle cx="330" cy="222" r="3" stroke-width="1"/><circle cx="342" cy="222" r="3" stroke-width="1"/><circle cx="354" cy="222" r="3" stroke-width="1"/>
  <rect x="370" y="216" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="330" y="260" font-size="12" font-weight="700" fill="currentColor" stroke="none">Acme Co · Client area</text>
  <text x="330" y="280" font-size="9.5" fill="currentColor" stroke="none" opacity="0.7">Shared with you</text>
  <rect x="330" y="290" width="200" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="330" y="303" width="170" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <rect x="330" y="316" width="185" height="7" rx="3" fill="currentColor" stroke="none" opacity="0.16"/>
  <circle cx="310" cy="210" r="11" stroke-width="1.5"/><text x="310" y="214" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">4</text>
  <path d="M290 95 H308" stroke-width="1.5" marker-end="url(#flowarrow-g5)"/><text x="299" y="88" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.6">next</text>
  <path d="M445 170 V190 H155 V208" stroke-width="1.5" opacity="0.6" marker-end="url(#flowarrow-g5)"/><text x="300" y="185" text-anchor="middle" font-size="10" fill="currentColor" stroke="none" opacity="0.6">invite a client</text>
  <path d="M290 285 H308" stroke-width="1.5" stroke-dasharray="6 4" opacity="0.6" marker-end="url(#flowarrow-g5)"/>
</svg>

<details>
<summary>Why it's shaped this way</summary>

- **Client access** — Per-project opt-in (`clientside_enabled`), off by default. Nothing is exposed until a team explicitly turns it on.
- **Share a resource** — `client_visible?` = `shared_with_client` **and** `published`. Publishing is the readiness gate, so a shared *draft* never leaks.
- **Invite a client** — Reuses the hardened invitation path (`accept!` / `consume!` with the `EmailMismatch` guard) but creates a `ClientAccess`, not a `Membership`.
- **Client area** — `ClientAccess` is a separate axis: clients consume no seat, never enter Pundit workspace policies, and the area never sets `Current.workspace`. They see only shared-and-published items.
</details>

## Extending these flows

Each **"Why"** points at the seam to build on. For the how-to, see [Extending the template](/docs/extending) and [Forking](/docs/forking); per-area depth lives in the feature docs linked at the top.
