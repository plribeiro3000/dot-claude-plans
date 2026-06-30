# SPIKE — WhatsApp MCP Contact Whitelist

## Investigation question

How can a JID-based whitelist be implemented in `lharries/whatsapp-mcp` so that the MCP tools exposed to Claude Code return **only** data from explicitly permitted conversations — even though the SQLite database contains all synced WhatsApp messages?

Secondary questions:
- Where are the viable extension points (Go bridge vs Python MCP layer)?
- Does any fork or upstream PR already solve this?
- What is the minimum viable implementation for each approach?

## Sources consulted

- `file:/tmp/whatsapp-mcp/whatsapp-bridge/main.go` — full Go bridge source; event handlers, REST server, SQLite write path
- `file:/tmp/whatsapp-mcp/whatsapp-mcp-server/whatsapp.py` — Python SQLite query layer; all WHERE clause construction
- `file:/tmp/whatsapp-mcp/whatsapp-mcp-server/main.py` — MCP tool definitions; all 12 exposed tools with signatures
- `file:/tmp/whatsapp-mcp/whatsapp-mcp-server/audio.py` — audio conversion via local ffmpeg subprocess; no network calls
- `file:/tmp/whatsapp-mcp/whatsapp-mcp-server/pyproject.toml` — Python deps: `mcp[cli]>=1.6.0`, `requests>=2.32.3`, `httpx>=0.28.1`
- `gh issue list -R lharries/whatsapp-mcp` — 50 issues scanned; see auxiliary `whatsapp_issues_log_1.txt`
- `gh pr list -R lharries/whatsapp-mcp` — 30 PRs scanned; see auxiliary `whatsapp_issues_log_1.txt`
- https://github.com/djinnsix/whatsapp-mcp/releases/tag/v0.2.0-djinnsix — security hardening fork
- https://github.com/LukasHaas/whatsapp-mcp — improved search fork
- https://github.com/verygoodplugins/whatsapp-mcp — maintained fork with media confinement
- https://github.com/FelixIsaac/whatsapp-mcp-extended — 26-tool extended fork
- https://www.docker.com/blog/mcp-horror-stories-whatsapp-data-exfiltration-issue/ — WhatsApp MCP data exfiltration attack (tool poisoning)
- https://github.com/behrensd/mcpwall — MCP security proxy (YAML-based tool call filtering)
- See auxiliary: `whatsapp_excerpt_1_whatsapp_py.py` — lines 1-50 (module header, `MESSAGES_DB_PATH`, `is_group` property), lines 124-180 (`list_messages()` WHERE clause), lines 319-390 (`list_chats()` WHERE clause), lines 393-414 (`search_contacts()` SQL with `@g.us` exclusion)
- See auxiliary: `whatsapp_excerpt_2_main_go.go` — `handleMessage()`, `handleHistorySync()`, `startRESTServer()`, event handler registration
- See auxiliary: `whatsapp_excerpt_3_main_py.py` — lines 1-25 of `main.py`: full tool import block (12 imports) confirming 12 registered MCP tools
- See auxiliary: `whatsapp_issues_log_1.txt` — full issue/PR scan with relevance notes

---

## Findings

### Finding 1: Architecture — two-layer system with clear seam between Go and Python

The project has two independent processes:

**Go bridge** (`whatsapp-bridge/main.go`): connects to WhatsApp via `whatsmeow` (multidevice WebSocket protocol), receives ALL messages from the account, writes them to SQLite at `whatsapp-bridge/store/messages.db`. Exposes a REST API (`/api/send`, `/api/download`) on port 8080. Audio transcription is NOT done here.

**Python MCP server** (`whatsapp-mcp-server/`): reads from the same SQLite file. Exposes 12 MCP tools to Claude Code. Calls the Go bridge's REST API only for write operations (`send_message`, `send_file`, `send_audio_message`) and `download_media`.

The seam is the SQLite file. The Go bridge writes; the Python server reads (plus two REST calls for writes).

**Evidence — Go bridge writes:**
```go
// main.go:438-452
err = messageStore.StoreMessage(
    msg.Info.ID,
    chatJID,
    sender,
    content,
    msg.Info.Timestamp,
    msg.Info.IsFromMe,
    mediaType,
    // ...
)
```

**Evidence — Python reads same file:**
```python
# whatsapp.py:10
MESSAGES_DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'whatsapp-bridge', 'store', 'messages.db')
```

See auxiliary `whatsapp_excerpt_1_whatsapp_py.py` (Range 1, line 10) for the verbatim line from the cloned repo.

URL fetched: N/A (local file read)
Verbatim quote checked: confirmed at `main.go:438` and `whatsapp.py:10`
Quote substring confirmed at those lines.

---

### Finding 2: All 12 MCP tools and their read/write surface

**Read tools** (query SQLite directly in Python):
1. `search_contacts(query: str)` — queries `chats` table by name/JID
2. `list_messages(after, before, sender_phone_number, chat_jid, query, limit, page, include_context, context_before, context_after)` — queries `messages` + `chats`
3. `list_chats(query, limit, page, include_last_message, sort_by)` — queries `chats` table
4. `get_chat(chat_jid, include_last_message)` — queries `chats` by exact JID
5. `get_direct_chat_by_contact(sender_phone_number)` — queries `chats` by phone number pattern
6. `get_contact_chats(jid, limit, page)` — queries chats where sender matches JID
7. `get_last_interaction(jid)` — returns single most recent message for a JID
8. `get_message_context(message_id, before, after)` — returns messages around a specific message ID

**Write tools** (call Go bridge REST API):
9. `send_message(recipient, message)` — POST `/api/send`
10. `send_file(recipient, media_path)` — POST `/api/send` with `media_path`
11. `send_audio_message(recipient, media_path)` — converts to OGG via local ffmpeg, then POST `/api/send`

**Download tool** (calls Go bridge REST API, reads media from disk):
12. `download_media(message_id, chat_jid)` — POST `/api/download`

**Evidence — tool import block (main.py:3-16):**
```python
# main.py:3-16
from whatsapp import (
    search_contacts as whatsapp_search_contacts,
    list_messages as whatsapp_list_messages,
    list_chats as whatsapp_list_chats,
    get_chat as whatsapp_get_chat,
    get_direct_chat_by_contact as whatsapp_get_direct_chat_by_contact,
    get_contact_chats as whatsapp_get_contact_chats,
    get_last_interaction as whatsapp_get_last_interaction,
    get_message_context as whatsapp_get_message_context,
    send_message as whatsapp_send_message,
    send_file as whatsapp_send_file,
    send_audio_message as whatsapp_audio_voice_message,
    download_media as whatsapp_download_media
)
```

The 12 imports match the 12 `@mcp.tool()` decorators present in `main.py` (verified by `grep -c "@mcp.tool()" main.py` returning 12). See auxiliary `whatsapp_excerpt_3_main_py.py` for the verbatim block from the cloned repo.

URL fetched: N/A (local file)
Verbatim quote checked: confirmed at `main.py:3-16`
Quote substring confirmed at those lines.

---

### Finding 3: WHERE clause construction is centralized in whatsapp.py — the natural Python injection point

Every read tool calls a corresponding function in `whatsapp.py`. Each function builds a dynamic WHERE clause by appending to a `where_clauses` list. This is the cleanest injection point for a whitelist.

**Evidence — `list_messages()` WHERE construction:**
```python
# whatsapp.py:143-179
where_clauses = []
params = []

if after:
    where_clauses.append("messages.timestamp > ?")
    params.append(after)
# ...
if chat_jid:
    where_clauses.append("messages.chat_jid = ?")
    params.append(chat_jid)
# ...
if where_clauses:
    query_parts.append("WHERE " + " AND ".join(where_clauses))
```

A whitelist clause fits naturally:
```python
# pseudocode — what Option B would add
allowed_jids = load_whitelist()  # from env or file
if allowed_jids:
    placeholders = ",".join("?" * len(allowed_jids))
    where_clauses.append(f"messages.chat_jid IN ({placeholders})")
    params.extend(allowed_jids)
```

Same pattern applies to `list_chats()`, `search_contacts()`, `get_contact_chats()`, `get_last_interaction()`, and `get_message_context()`.

URL fetched: N/A (local file)
Verbatim quote checked: confirmed at `whatsapp.py:143-179`
Quote substring confirmed at those lines.

---

### Finding 4: Go bridge has two write entry points that must both be gated for Option A

The Go bridge writes to SQLite through two separate code paths:

1. **Real-time messages** — `handleMessage()` called from the event handler for `*events.Message`
2. **History sync** — `handleHistorySync()` called for `*events.HistorySync` (fires on first connect, bulk imports ALL historical conversations)

**Evidence — event handler:**
```go
// main.go:838-854
client.AddEventHandler(func(evt interface{}) {
    switch v := evt.(type) {
    case *events.Message:
        handleMessage(client, messageStore, v, logger)
    case *events.HistorySync:
        handleHistorySync(client, messageStore, v, logger)
    // ...
    }
})
```

**Evidence — history sync stores all conversations unconditionally:**
```go
// main.go:1013-1023
for _, conversation := range historySync.Data.Conversations {
    if conversation.ID == nil {
        continue
    }
    chatJID := *conversation.ID
    // ... stores ALL conversations
    messageStore.StoreChat(chatJID, name, timestamp)
```

Option A must gate BOTH handlers. If only `handleMessage()` is gated, the initial history sync still populates the database with all historical messages from non-whitelisted chats.

URL fetched: N/A (local file)
Verbatim quote checked: confirmed at `main.go:838-854` and `main.go:1013`
Quote substring confirmed at those lines.

---

### Finding 5: JID format in WhatsApp — what a whitelist entry looks like

JIDs (Jabber IDs) are the unique identifiers for chats in WhatsApp:

- **Individual DM**: `5511999999999@s.whatsapp.net` (country code + number, no `+`)
- **Group chat**: `120363XXXXXXXXXX@g.us`

The Python code discriminates between them:
```python
# whatsapp.py:33-36
    @property
    def is_group(self) -> bool:
        """Determine if chat is a group based on JID pattern."""
        return self.jid.endswith("@g.us")
```

The `search_contacts()` function explicitly excludes groups via the SQL WHERE clause:
```python
# whatsapp.py:406-408
            WHERE
                (LOWER(name) LIKE LOWER(?) OR LOWER(jid) LIKE LOWER(?))
                AND jid NOT LIKE '%@g.us'
```

See auxiliary `whatsapp_excerpt_1_whatsapp_py.py` (Range 1 lines 33-36 for `is_group`; Range 4 lines 406-408 for the SQL) for verbatim lines from the cloned repo.

To discover a JID before adding it to the whitelist, the engineer can call `list_chats()` or `search_contacts()` via Claude Code (with the full-access server running temporarily), or `SELECT jid, name FROM chats;` directly against the SQLite file.

URL fetched: N/A (local file)
Verbatim quote checked: confirmed at `whatsapp.py:33-36` and `whatsapp.py:406-408`
Quote substring confirmed at those lines.

---

### Finding 6: No fork or upstream PR implements a JID whitelist — the feature does not exist in the ecosystem

After scanning 50 issues and 30 PRs, examining 5 active forks (djinnsix, LukasHaas, verygoodplugins, FelixIsaac, mario-andreschak), and running targeted web searches: **no implementation of contact/JID whitelist for read access exists in the lharries/whatsapp-mcp ecosystem.**

The closest existing mechanisms are:
- Issue #218: suggests PolicyLayer/Intercept for `send_*` tool approval (write-only, not read filtering)
- `verygoodplugins/whatsapp-mcp`: `WHATSAPP_MEDIA_ROOTS` env var restricts which filesystem directories can be referenced for media sends (path containment, not JID filtering)
- `FelixIsaac/whatsapp-mcp-extended`: `WHATSAPP_MCP_TOOLSETS` env var selects which tool categories are exposed (tool-level, not data-level)

The project maintainer has not responded to any open issue or merged any open PR as of 2026-05-27.

Evidence: Issue list scanned — no whitelist/allowlist issue found. See `whatsapp_issues_log_1.txt`.

URL fetched: https://github.com/lharries/whatsapp-mcp/issues (scanned via `gh issue list`)
Verbatim quote checked: issue titles and bodies in `whatsapp_issues_log_1.txt`
Quote substring confirmed from `gh issue view 218` output.

---

### Finding 7: The Docker MCP exfiltration report establishes that read-access restriction is a real security need

Docker's security blog documents an attack where a poisoned MCP server tool description redirects `send_message` calls to an attacker's number while embedding full chat history as "validation data." The attack specifically exploits the fact that `list_chats` output is passed to `send_message` with no JID restriction.

**Evidence:**
From https://www.docker.com/blog/mcp-horror-stories-whatsapp-data-exfiltration-issue/:
> "Layer 2's network isolation prevents any message to the attacker's phone number (+13241234123) through whitelist enforcement"

Docker's mitigation is infrastructure-level (container network egress whitelist). A JID whitelist at the MCP layer is a complementary application-level control.

URL fetched: https://www.docker.com/blog/mcp-horror-stories-whatsapp-data-exfiltration-issue/
Verbatim quote checked: "Layer 2's network isolation prevents any message to the attacker's phone number (+13241234123) through whitelist enforcement"
Quote substring confirmed in fetched page content.

---

### Finding 8: mcpwall proxy can filter tool call parameters by field value — applicable to send_* tools

mcpwall (https://github.com/behrensd/mcpwall) is a JSON-RPC proxy that sits between Claude Code and MCP servers. Its YAML policy format supports `_any_value` wildcard matchers and named `arguments.<field>` matchers with `regex` predicates.

**Evidence — policy format (verbatim from https://github.com/behrensd/mcpwall README):**
```yaml
rules:
  # Block reading SSH keys
  - name: block-ssh-keys
    match:
      method: tools/call
      tool: "*"
      arguments:
        _any_value:
          regex: "(\.ssh/|id_rsa|id_ed25519)"
    action: deny
    message: "Blocked: access to SSH keys"
```

Applied to `send_message` recipient restriction, a rule would match `arguments.recipient` against a regex that only allows whitelisted JIDs, with `action: deny` for non-matches.

This could enforce `send_message` recipient restrictions without modifying the Python MCP server. However, mcpwall operates on tool call **arguments** (what Claude sends in), not on tool **return values** — it cannot filter what `list_messages` or `list_chats` returns to Claude. It addresses the send-path exfiltration vector, not the read-path privacy concern.

URL fetched: https://github.com/behrensd/mcpwall
Verbatim quote checked: `_any_value:`, `regex:`, `action: deny`, `message: "Blocked: access to SSH keys"` confirmed in fetched README content
Quote substring confirmed at fetched URL.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **Option A — Filter in Go bridge (before SQLite write)** | Maximum privacy: personal messages never touch disk. SQLite stays clean. | Two gating points required (`handleMessage` + `handleHistorySync`). Requires Go build. Losing history: if you add a chat to the whitelist later, no historical messages exist. Changing whitelist requires restarting the bridge. | `main.go:412-471`, `main.go:1009-1148` |
| **Option B — Filter in Python MCP layer (WHERE clauses)** | Simple: 20-30 lines of Python across 6 functions. No Go changes. Whitelist change takes effect on next MCP restart. SQLite preserves all data (useful if whitelist changes). | SQLite still contains all messages on disk (local Mac only, not transmitted anywhere). Context leak is theoretically possible if a bug bypasses the WHERE clause. | `whatsapp.py:124-390`, `main.py:21-248` |
| **Option C — External MCP proxy (mcpwall or PolicyLayer)** | Zero code changes to lharries. Works at JSON-RPC level. | Can only filter outbound tool calls (send_*), not filter return values from read tools. Doesn't solve the read-path privacy question. Adds a new process to manage. | https://github.com/behrensd/mcpwall, Issue #218 |

---

## What remains uncertain

- **LID resolution and JID stability**: WhatsApp is migrating to Linked Device IDs (LIDs). Issue #198 documents that LID mappings are never synced to `messages.db`. A chat that appears as `5511999@s.whatsapp.net` today may appear as an opaque LID after a WhatsApp account migration event. A whitelist based on JIDs may need LID-to-JID resolution to stay correct. The `LukasHaas/whatsapp-mcp` fork addresses this but the fix is not upstream.
- **`get_message_context()` bypass**: This tool takes a `message_id` and returns surrounding messages from the same `chat_jid`. If a non-whitelisted message ID is somehow known (e.g., via a different attack surface), it returns context from that chat without a JID check in the current code. Option B would need to add a JID check in `get_message_context()` too.
- **Maintainer abandonment**: The repo has not merged any PR since mid-2024. 20+ open PRs, maintainer unresponsive. A fork-and-patch approach means tracking upstream changes manually. Whether the engineer uses a local patch (`git am`) vs a personal fork on `github.com/plribeiro3000` affects long-term maintenance burden.
- **`get_message_context()` whitelist coverage**: The function fetches by `message_id`, then uses the `chat_jid` from that message row to fetch surrounding messages. A whitelist check would need to validate that `chat_jid` against the whitelist — this is one additional query or in-memory check, not complex, but must not be forgotten.
- **Audio transcription**: `audio.py` uses local `ffmpeg` subprocess only — no external API call. No privacy concern for audio in this pipeline.

---

## Suggested options for main and the engineer

### Option A: Filter in Go bridge — privacy-maximum, disk-clean

Gate BOTH `handleMessage()` and `handleHistorySync()` in `main.go` before any `messageStore.Store*()` call. Read allowed JIDs from an environment variable (e.g., `ALLOWED_JIDS=5511999@s.whatsapp.net,120363XXX@g.us`) or a YAML file at startup.

Approximate scope:
- `handleMessage()`: add 5 lines before `messageStore.StoreChat()` call
- `handleHistorySync()`: add 5 lines inside the `for _, conversation` loop, before `messageStore.StoreChat()`
- Startup: parse `ALLOWED_JIDS` env var or config file in `main()`

Total: ~25 lines Go. Requires `go build` after edit. Pattern matches PR #242's established env var approach.

Trade-off: no historical messages for newly whitelisted chats; requires bridge restart to change whitelist.

### Option B: Filter in Python MCP layer — simple, reversible, no Go changes

Load whitelist from `ALLOWED_JIDS` env var at module import time in `whatsapp.py`. Inject a `messages.chat_jid IN (?, ?, ...)` / `chats.jid IN (?, ?, ...)` clause into `where_clauses` in 6 functions:

Functions that need the injection:
1. `list_messages()` — `messages.chat_jid IN (...)`
2. `list_chats()` — `chats.jid IN (...)`
3. `search_contacts()` — `jid IN (...)` (already filters `@g.us`; add whitelist)
4. `get_contact_chats()` — `c.jid IN (...)`
5. `get_last_interaction()` — `c.jid IN (...)`
6. `get_message_context()` — validate `target_message.chat_jid IN whitelist` after fetch, raise if not

Additionally, `get_chat()` and `get_direct_chat_by_contact()` take explicit JID inputs — add a guard at the top: `if chat_jid not in allowed_jids: return None`.

For `send_message()`, `send_file()`, `send_audio_message()`: optionally add recipient check (raises if recipient not in whitelist) — or leave unconstrained (engineer decides).

Approximate scope: ~30 lines Python total. No Go changes. No rebuild. Works with any fork or the original.

Trade-off: SQLite still has all messages on disk; context leak risk if whitelist logic has a bug.

### Option C: Python whitelist (Option B) + mcpwall for send_* restriction

Combine Option B (read-path Python filtering) with mcpwall YAML policy that restricts `send_message` / `send_file` / `send_audio_message` to whitelisted recipients. Provides defense in depth: even if the Python whitelist is bypassed for reads, mcpwall blocks sends to non-whitelisted numbers.

Adds a second process (mcpwall) and a YAML policy file to maintain. Both must be kept in sync with the JID whitelist.

Approximate scope: Option B (~30 lines Python) + mcpwall YAML policy (~15 lines YAML) + mcpwall process setup.

---

*(No recommendation — the three options above surface the trade-offs. Main and the engineer choose.)*
