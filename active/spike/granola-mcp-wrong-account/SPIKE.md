# SPIKE — Granola MCP connector stuck on the wrong account

**Date:** 2026-07-14
**Status:** Closed — root cause found, fix plan ready (engineer executes interactively).
**Question:** Claude Code keeps reporting the Granola MCP as connected to `plribeiro3000@gmail.com` (personal) even after the engineer deleted the Granola website cookie and reconnected in Claude Code with `paulo@4shark.com.br` (4Shark). Result: today's meetings (under the 4Shark account) are invisible. Is this a known bug, and how is it fixed?

## Evidence (this session)

- `get_account_info` → `{"email":"plribeiro3000@gmail.com", "active_workspace":{"display_name":"Paulo Ribeiro"}}` — the connector is bound to the **personal** account.
- `list_meetings last_30_days` → only 1 unrelated meeting ("Financing options for property", Jul 8); `custom 2026-07-13..15` → 0. The 4Shark meetings simply are not in the account the connector sees.
- `claude mcp list` shows **two** Granola registrations at the same URL `https://mcp.granola.ai/mcp`:
  - `claude.ai Granola` — **✔ Connected** (a **claude.ai-managed connector** — this is what the tools resolve to, holding the stale personal token)
  - `granola` (HTTP, locally added) — `! Needs authentication` (a duplicate registration)
- `~/.claude/mcp-needs-auth-cache.json` lists only monday.com as needing auth — the client believes the claude.ai Granola connector is healthy; it just carries the wrong-account grant.

## Root cause

The "claude.ai Granola" entry is a **claude.ai-account-level remote connector**. Its OAuth grant to Granola is stored **server-side at claude.ai** (tied to the Claude account), not in a local Granola cookie. So:

- Deleting the **Granola website** cookie and reconnecting from the Claude Code CLI did **not** clear the claude.ai↔Granola grant — that grant still points at the personal Granola account, so every session resolves to `plribeiro3000@gmail.com`.
- The original mis-bind is a **known Claude Code bug**: a remote MCP connector OAuth silently authorizes the **wrong account** when the browser is logged into a different account than intended during the OAuth flow.
  - [anthropics/claude-code #40915](https://github.com/anthropics/claude-code/issues/40915) — "Remote MCP connector OAuth silently authorizes wrong account when browser and Claude Code Desktop use different accounts." **Closed as duplicate of #35658.**
  - [anthropics/claude-code #35658](https://github.com/anthropics/claude-code/issues/35658) — canonical issue; **closed as not planned** (no code fix). Documented workaround: *"Ensure the browser is logged into the same account as Claude Code before attempting OAuth authentication."*
- Compounding clutter: a second, duplicate `granola` HTTP server was added locally, so even a correct re-auth could land on the wrong registration.

## Fix — the Granola-specific reconnection (engineer runs; OAuth needs a browser)

The reliable community workaround for switching a Granola connector to a different account uses an **incognito window** so no personal-account session bleeds into the OAuth flow (this is what defuses #40915). Source: Granola support guidance surfaced via [Claude MCP connectors help](https://support.claude.com/en/articles/14503689-mcp-connectors) and the Granola reconnect steps.

**Where "revoke Claude's access" actually lives:** there is **no Granola-side UI** to remove the "Claude" app for an MCP consumer. The Claude↔Granola OAuth grant is managed on the **client side — claude.ai → Settings → Connectors → Granola → Disconnect**. That Disconnect *is* the revocation. (The Google/Microsoft "remove Granola" permission pages revoke Granola's access to your *calendar*, a different relationship — not relevant here.)

Why a plain reconnect failed (verbatim, [MCP connectors help](https://support.claude.com/en/articles/14503689-mcp-connectors) / Granola reconnect guidance): *"your existing Granola session stays active, so it skips the login step. Incognito forces a fresh login, which lets you pick the right account."* Granola MCP is browser OAuth with Dynamic Client Registration — no client ID/secret to manage.

Ordered steps (engineer runs the browser/terminal steps; agent verifies at the end):

1. *(Optional)* Fully quit the Claude Code app so it is not holding the live connection.
2. Open an **incognito/private** browser window.
3. Go to **claude.ai** → sign in with the **4Shark** Claude account (the one this Claude Code is logged into).
4. **Settings → Connectors → Granola → three-dot menu → Disconnect.** ← this revokes Claude's current (personal-account) access.
5. **Without closing the window or navigating away**, click **Connect** on Granola again.
6. On the Granola OAuth screen — incognito means no active session → it forces a fresh login → sign in as **`paulo@4shark.com.br`** and authorize. (If it still auto-picks the personal account, open `granola.ai` in that same incognito window, confirm/switch to the 4Shark account there, then redo 4–6.)
7. Remove the duplicate local registration: `claude mcp remove granola` — keep only the single `claude.ai Granola` connector.
8. If the account is still wrong after step 6, clear the cached token and restart: `claude mcp logout "claude.ai Granola"`, then fully quit and reopen Claude Code (on macOS the token may live in the login Keychain under the Claude Code credential entry — remove that entry only if the logout does not clear it).
9. **Verify in a fresh Claude Code session:** `get_account_info` → `paulo@4shark.com.br`; `list_meetings this_week` → the 4Shark meetings appear (incl. today's 08:00 Maqnelson meeting).

## Notes

- The OAuth/browser steps cannot run from this non-interactive session — the engineer performs steps 1–6 (and 8's restart); the agent verifies step 9.
- Keep a **single** Granola registration. Two entries at the same URL is the state that made this ambiguous; step 7 removes it.
- No upstream fix exists (#35658 closed not-planned) — the incognito reconnect is the durable workaround, not a temporary patch.
