---
title: Application Flows
description: A builder's guide to the app's core journeys for developers and designers extending the template — clean wireframes paired with full-size prose explaining the why (the framework decision, seam, or guarantee) behind each screen, on a domain-model primer.
keywords: wireframes flows builder guide developers designers why rationale model workspace membership role onboarding seam readable
---

# Application Flows

For **developers and designers extending this template**. Each flow shows the screens as a wireframe; the **"Why"** beneath it — rendered as normal, readable prose — explains the framework decision, the seam you'd extend, or the guarantee it gives you. The end-user flows are intentionally tight, so this page is for *builders*, not users. For the full detail behind each journey, follow the per-flow links to [Email & verification](/docs/user/emails), [Onboarding](/docs/user/onboarding), and [Workspaces](/docs/user/workspaces).

## The model behind every flow

Three concepts the flows plug into — knowing these is usually enough to avoid fighting the template. A fork adds its own tenant-scoped domain models (via the `Tenanted` concern) alongside this core.

| Concept | What it is | Why it's shaped this way |
| --- | --- | --- |
| `User` | One identity / login | Reused across workspaces — one person, many memberships. |
| `Workspace` | The tenant | Top-level boundary; `Current.workspace` scopes data via the `Tenanted` concern. |
| `Membership` + `Role` | owner · admin · member · viewer | Role is **per-workspace, not global** (JSON permissions); Pundit authorizes. |

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

<svg viewBox="0 0 300 200" width="100%" role="img" aria-label="First-run onboarding, one step. Name your workspace, field Workspace name, Continue." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <rect x="20" y="20" width="270" height="160" rx="11" stroke-width="1.5"/>
  <line x1="20" y1="44" x2="290" y2="44" stroke-width="1"/>
  <circle cx="40" cy="32" r="3" stroke-width="1"/><circle cx="52" cy="32" r="3" stroke-width="1"/><circle cx="64" cy="32" r="3" stroke-width="1"/>
  <rect x="80" y="26" width="200" height="12" rx="6" stroke-width="1" opacity="0.5"/>
  <text x="40" y="72" font-size="12.5" font-weight="700" fill="currentColor" stroke="none">Name your workspace</text>
  <text x="40" y="94" font-size="9.5" fill="currentColor" stroke="none" opacity="0.7">Workspace name</text>
  <rect x="40" y="99" width="220" height="18" rx="4" stroke-width="1"/><text x="48" y="111.5" font-size="10" fill="currentColor" stroke="none" opacity="0.45">Acme Co</text>
  <rect class="text-accent" x="40" y="132" width="120" height="21" rx="6" stroke-width="2.25"/><text class="text-accent" x="100" y="146.5" text-anchor="middle" font-size="10.5" font-weight="700" fill="currentColor" stroke="none">Continue</text>
  <circle cx="20" cy="20" r="11" stroke-width="1.5"/><text x="20" y="24" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">1</text>
</svg>

<details>
<summary>Why it's shaped this way</summary>

- **Name your workspace** — Onboarding only runs under `WORKSPACE_ON_SIGNUP=none`; the `RequiresOnboarding` guard is posture-gated and html-only, returning early in every other posture. It is a single step: creating the workspace stamps `onboarded_at` immediately, since the example domain that used to add project/tools/team steps here has been removed. A fork that wants a multi-step wizard adds its own steps back around its own domain models.
</details>

## 3 · Invite teammates

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

## Extending these flows

Each **"Why"** points at the seam to build on. For the how-to, see [Extending the template](/docs/developer/extending) and [Forking](/docs/developer/forking); per-area depth lives in the feature docs linked at the top.
