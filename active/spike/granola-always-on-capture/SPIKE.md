# SPIKE — Granola Always-On / Ad-Hoc Call Capture (Slack Huddles and Beyond)

## Investigation question

The engineer records meetings with Granola, which today works from the calendar: before a scheduled meeting it shows a "join" button and auto-starts recording when the engineer joins. The gap is ad-hoc, non-calendar conversations — concretely, a Slack huddle with the internal team — which Granola misses because there is no calendar event to trigger it.

The desired workflow to evaluate for feasibility:

1. Granola stays "active"/always-listening and detects entry into ANY app or call (Slack huddle, ad-hoc Meet, Zoom, Teams, FaceTime, etc.), not only calendar-linked meetings.
2. When a call starts, Granola checks the calendar: if a matching agenda item exists, it attaches notes to that event.
3. If no match exists, it creates an ad-hoc note and captures anyway.
4. When the conversation ends, Granola auto-corrects/renames the note title.

Sub-questions A–F (audio-capture mechanism, Slack-huddle-specific support, retroactive calendar linking, auto-title-renaming, automation surface, and alternatives) are answered below.

## Sources consulted

- [docs.granola.ai/help-center/taking-notes/transcription](https://docs.granola.ai/help-center/taking-notes/transcription) — how Granola captures audio, ad-hoc note detection, auto-stop behavior
- [docs.granola.ai/help-center/taking-notes/notifications](https://docs.granola.ai/help-center/taking-notes/notifications) — the "call detected" / "Huddle detected" / "Meeting detected" notification mechanism, the single closest native feature to "always-on ambient detection"
- [www.granola.ai/blog/how-to-use-granola-slack-huddles](https://www.granola.ai/blog/how-to-use-granola-slack-huddles) — Granola's own guidance specifically for Slack huddles
- [docs.granola.ai/help-center/sharing/integrations/zapier](https://docs.granola.ai/help-center/sharing/integrations/zapier) — Zapier triggers/payload shape
- [docs.granola.ai/introduction](https://docs.granola.ai/introduction) — the official public REST API, its two endpoints, and their read-only scope
- [github.com/getprobo/reverse-engineering-granola-api](https://github.com/getprobo/reverse-engineering-granola-api) — archived reverse-engineered API surface (superseded by the official API, but documents endpoints the official docs page didn't enumerate)
- [docs.granola.ai/help-center/getting-started/syncing-your-calendars](https://docs.granola.ai/help-center/getting-started/syncing-your-calendars) — how Granola matches notes to calendar events (recurring-event-ID + exact-title matching)
- [docs.granola.ai/help-center/taking-notes/ai-enhanced-notes](https://docs.granola.ai/help-center/taking-notes/ai-enhanced-notes) — fetched directly; contains no title-renaming mechanism (used as a negative finding for D)
- [zackproser.com/granola](https://zackproser.com/granola) — a 12-months-in personal review; used for real-world ad-hoc/non-calendar usage friction
- [www.shadow.do/blog/best-ai-meeting-assistants-for-slack-huddles-2026](https://www.shadow.do/blog/best-ai-meeting-assistants-for-slack-huddles-2026) — competitor comparison specifically on the Slack-huddle/always-on axis
- [www.shadow.do/blog/how-to-record-slack-huddle-on-mac-automatically](https://www.shadow.do/blog/how-to-record-slack-huddle-on-mac-automatically) — Shadow's own auto-trigger claim
- [techcrunch.com/2026/04/15/fathom-adds-a-bot-less-meeting-mode-in-a-bid-to-take-on-granola](https://techcrunch.com/2026/04/15/fathom-adds-a-bot-less-meeting-mode-in-a-bid-to-take-on-granola/) — Fathom's April 2026 bot-free launch, direct competitive response to Granola
- WebSearch (not directly fetched, used for corroboration only, flagged inline as UNVERIFIED where the underlying page was not fetched): macOS `ScreenCaptureKit` technical mechanism, Rewind/Limitless pendant and desktop app, Fellow "Botless Recording"

## Findings

### Finding A1 — Granola's native "always-on ambient detection" exists, but it is detect-and-prompt, not silent-and-automatic

**Evidence:** "Granola can detect calls held in most platforms, even if it's not in your calendar. By detecting that your microphone is in use, Granola will prompt you to take notes." The notification titles are platform-specific: "Huddle detected" for Slack, "Call detected" for FaceTime or WhatsApp, and "Meeting detected" for other applications. Starting the capture still requires the user to click "Take Notes" — the notification is a prompt, not an automatic recorder.

**Source:** [docs.granola.ai/help-center/taking-notes/notifications](https://docs.granola.ai/help-center/taking-notes/notifications), directly fetched.

**Significance:** This is the closest native match to desired-workflow item 1 ("Granola stays active and detects entry into ANY app or call"). It runs at the OS level (microphone-in-use detection), is platform-agnostic (works for Slack, FaceTime, WhatsApp, "most platforms"), and needs no calendar event. But it stops short of the engineer's literal ask — it surfaces a notification the engineer must click, it does not silently begin capturing on its own.

### Finding A2 — Audio capture is a system-audio tap via macOS ScreenCaptureKit, not a meeting bot and not a per-app integration

**Evidence:** "Granola runs only on your computer and uses your system audio and microphone" and "uses your system audio to capture transcription, capturing whatever audio inputs and outputs happen on your computer." This is architecture-agnostic to the calling app — it captures whatever audio macOS is playing/recording, regardless of which app produced it.

**Source:** [docs.granola.ai/help-center/taking-notes/transcription](https://docs.granola.ai/help-center/taking-notes/transcription), directly fetched.

**Significance:** Because capture is system-audio-level (not a Slack-specific or Zoom-specific integration), Slack huddles are technically capturable by the same mechanism as any other call — there is nothing Slack-specific blocking it. This is corroborated independently by a competitor's technical framing: "if it joins as a participant tile, it doesn't work. If it captures system audio from your Mac, it does" — naming Granola, Shadow, Krisp, and Fellow as tools using this device-side approach, versus Otter/Fathom(pre-2026)/tl;dv/Read.ai, which historically had "no native Slack Huddle support" because they relied on meeting-bot join APIs that Slack huddles have no join surface for.

**Source:** [www.shadow.do/blog/best-ai-meeting-assistants-for-slack-huddles-2026](https://www.shadow.do/blog/best-ai-meeting-assistants-for-slack-huddles-2026), directly fetched.

**UNVERIFIED (technical mechanism detail, WebSearch-only, not directly fetched from an Apple/Granola primary source):** the specific claim that Granola implements this via Apple's `ScreenCaptureKit` API with `SCStream`/`capturesAudio` and requires the macOS "Screen & System Audio Recording" permission grant. This came from a WebSearch synthesis, not a page I fetched and confirmed a verbatim quote from — flagging per citation discipline rather than asserting it as sourced fact. It is consistent with A2's confirmed capture description (system-audio tap, no driver) and with how ScreenCaptureKit works generally, but the Granola-specific attribution is unverified.

### Finding B1 — Slack huddles specifically: Granola's own guidance is "no auto-detect from calendar, use New Note manually" — but the notification (A1) also fires for huddles

**Evidence:** "No. Granola detects meetings from your Google or Microsoft calendar. Because Huddles are typically ad-hoc and don't appear on your calendar, you need to open a new note manually before or when the call starts." This is Granola's FAQ-style answer to "does Granola auto-join/auto-detect huddles the way it does calendar meetings." Separately, the same blog post confirms system-audio capture works for huddles once a note is manually opened: "Granola transcribes audio directly from your device, picking up both your microphone input and the system audio playing through your computer," with "no participant to invite, no announcement that transcription has started, and no visible presence in the Huddle itself."

**Source:** [www.granola.ai/blog/how-to-use-granola-slack-huddles](https://www.granola.ai/blog/how-to-use-granola-slack-huddles), directly fetched.

**Significance:** These two sources (this blog post and the Notifications doc, A1) are not contradictory once read together — they describe two different mechanisms. Calendar-based auto-detect (the mechanism the blog's FAQ answer is denying) genuinely does not apply to huddles. But the separate "Huddle detected" microphone-in-use notification (A1) DOES fire for huddles specifically, per the Notifications doc's own platform-specific title list. The practical result: the engineer still needs to act on a prompt (click "Take Notes" on the notification, or manually hit New Note) — Granola does not silently start recording a huddle with zero user action.

### Finding C1 — Calendar-linking of an ad-hoc note happens at note-creation time, by time-proximity, not by later re-matching

**Evidence:** "If you initiate a meeting within 15 minutes after a scheduled calendar event, Granola assumes it's related to that event and displays the calendar event name in the notification instead." This applies to the "call detected" notification prompt itself — the calendar match, when it happens, happens at prompt time based on a 15-minute proximity window to an existing calendar event.

**Source:** [docs.granola.ai/help-center/taking-notes/notifications](https://docs.granola.ai/help-center/taking-notes/notifications), directly fetched.

**Significance:** This partially satisfies desired-workflow item 2 ("if there is an agenda item that maps to this conversation, attach the notes to that event") — but only for events within a narrow 15-minute window right before the call starts, and matched at the moment of detection, not by any content/topic matching against the whole day's agenda.

### Finding C2 — No evidence of retroactive linking of an already-created ad-hoc note to a calendar event discovered later

**Evidence:** Granola's calendar-matching for showing related notes together uses "the recurring event ID from your calendar, and the exact meeting title. Meetings that share the same recurring event ID or have exactly the same title will appear as related." This is how Granola groups a *series* of recurring-meeting notes, not a mechanism for attaching a manually-created ad-hoc note to an event it wasn't started near. No documentation page found (across the Notifications, Transcription, Syncing Your Calendars, Zapier, or API pages) describes an explicit "attach this note to that calendar event" action available after the note already exists.

**Source:** [docs.granola.ai/help-center/getting-started/syncing-your-calendars](https://docs.granola.ai/help-center/getting-started/syncing-your-calendars), directly fetched.

**Significance:** Not found: a documented feature for the specific case in desired-workflow item 2 where the engineer starts a huddle capture, and only afterward realizes/wants it associated with a calendar item that wasn't within the 15-minute detection window. This is a genuine gap versus the engineer's described workflow, not merely an unconfirmed claim — the relevant Granola documentation pages were read and the mechanism was not present in any of them.

### Finding D1 — No documented automatic content-based title renaming for ad-hoc notes; Granola's own guidance is to name the note manually

**Evidence:** Granola's own Slack-huddles guidance instructs the user to actively choose a title: "You should name the note with something identifiable, such as 'Design sync - Feb 25,' so it's searchable later." The AI-Enhanced Notes documentation page — which is where a "generate title from transcript" feature would be documented if it existed — was fetched directly and "does not contain any information about automatic title generation, title renaming, or how note titles are determined... there is no discussion of titling mechanisms."

**Source:** [www.granola.ai/blog/how-to-use-granola-slack-huddles](https://www.granola.ai/blog/how-to-use-granola-slack-huddles) and [docs.granola.ai/help-center/taking-notes/ai-enhanced-notes](https://docs.granola.ai/help-center/taking-notes/ai-enhanced-notes), both directly fetched.

**Significance:** Desired-workflow item 4 ("auto-correct/rename the note title when the conversation ends") does not appear to be a documented, shipped Granola feature. For calendar-linked meetings, the title comes from the calendar event itself (not from content). For ad-hoc notes, Granola's own advice to users is to type a title themselves at creation time — the opposite of automatic post-hoc renaming. This is a documentation-based negative finding (an absence of the feature in the pages that would document it), not a confirmed "Granola cannot do this" from a support statement — treat as "not found," not as a denial from Granola.

### Finding E1 — The official public API is read-only (List Notes, Get Note); no write/create/start-recording endpoint exists

**Evidence:** "The Granola API provides programmatic access to your workspace's meeting notes and related data. This RESTful API enables you to integrate Granola with your existing tools, build custom workflows, and extract insights from your meeting documentation." The only two documented endpoints are a List Notes endpoint (paginated) and a Get Note endpoint (optionally including the transcript). No endpoint for creating a note, starting/stopping a recording, or linking a note to a calendar event is documented.

**Source:** [docs.granola.ai/introduction](https://docs.granola.ai/introduction), directly fetched.

**Significance:** The API cannot be used to build the "detect any call → trigger Granola to start capturing" half of the automation loop described in desired-workflow item 1/5 — it can only be used downstream, to read/relay a note's *content* after Granola itself has already captured it (e.g., for the auto-relink or auto-rename half, glue code could rewrite a note's association or title in some *other* system it forwards to, but not inside Granola itself, since there's no write endpoint).

### Finding E2 — The now-archived reverse-engineered API surface confirms the same read-only shape, with slightly more endpoints (workspaces, folders, batch fetch) — still nothing for triggering capture

**Evidence:** The archived repository lists: `POST /user_management/authenticate` (WorkOS token refresh), `POST /v2/get-documents`, `POST /v1/get-document-transcript`, `POST /v1/get-workspaces`, `POST /v2/get-document-lists`, `POST /v1/get-documents-batch`. The repository itself states: "⚠️ ARCHIVED: This repository is now archived. Granola has released an official API, making this reverse-engineering effort obsolete."

**Source:** [github.com/getprobo/reverse-engineering-granola-api](https://github.com/getprobo/reverse-engineering-granola-api), directly fetched.

**Significance:** Confirms E1's conclusion from a second, independent (unofficial) source: even the deeper, previously-undocumented internal API surface had no endpoint to programmatically create a note or start a capture. Both the sanctioned and the reverse-engineered surfaces are read-only for capture purposes.

### Finding E3 — Zapier integration is trigger-only (note-created / note-shared), not action-capable for starting a capture

**Evidence:** The two documented Zapier triggers are: "Note Added to Granola Folder: Automatically triggers when a note is added to a specific folder" and "Note Shared to Zapier: Triggers when you manually share a note to Zapier from the note sidebar." The webhook payload Zapier receives on trigger contains "the meeting note title, creator name and email, attendees list with names and emails, and calendar event details including the event title and date/time" — i.e., data flowing OUT of Granola after a note already exists, not a way to push a "start capturing now" instruction IN.

**Source:** [docs.granola.ai/help-center/sharing/integrations/zapier](https://docs.granola.ai/help-center/sharing/integrations/zapier), directly fetched.

**Significance:** No native automation surface (API or Zapier) exists to programmatically trigger Granola to start listening for an arbitrary detected app/call. The only inbound-triggerable behavior in Granola today is the OS-level microphone-detection notification (Finding A1), which is not exposed as an API — it's a built-in background service, not something a third-party watcher script can invoke.

### Finding F1 — Among comparable competitors, none is fully calendar-independent by default; two (Shadow, Fathom's new mode) claim closer-to-automatic capture than Granola for ad-hoc calls

**Evidence — Shadow (closest to the engineer's literal ask):** "Shadow offers 'True meeting auto-detection' where it detects when a meeting actually starts at the OS level — not based on a calendar event, not based on a browser asking for mic permission... Open a Slack Huddle, and Shadow notices. Close it, and Shadow stops. You don't have to remember to record anything." And, separately: "automatically triggers when you join a Slack Huddle, so you don't have to manually start and stop the recording... Once you've set it up, Shadow will automatically start recording your Slack Huddles." Shadow is explicitly "Mac-only."

**Source:** [www.shadow.do/blog/best-ai-meeting-assistants-for-slack-huddles-2026](https://www.shadow.do/blog/best-ai-meeting-assistants-for-slack-huddles-2026) and [www.shadow.do/blog/how-to-record-slack-huddle-on-mac-automatically](https://www.shadow.do/blog/how-to-record-slack-huddle-on-mac-automatically), both directly fetched.

**Evidence — Fathom's April 2026 bot-free mode:** Fathom's CEO's stated differentiator versus bot-free peers (naming Granola implicitly) is speaker diarization: "A lot of these bot-less tools don't indicate who said what in their captured transcript" — Fathom's new mode adds "speaker diarization" on top of the same general bot-free approach. The article frames this launch explicitly as "a direct competitive response to Granola."

**Source:** [techcrunch.com/2026/04/15/fathom-adds-a-bot-less-meeting-mode-in-a-bid-to-take-on-granola](https://techcrunch.com/2026/04/15/fathom-adds-a-bot-less-meeting-mode-in-a-bid-to-take-on-granola/), directly fetched.

**Evidence — the other mainstream tools remain calendar/bot-dependent:** "Fireflies, Fathom, Otter, and Fellow can all be configured to auto-join any meeting on your calendar" but "these tools are primarily calendar-dependent rather than truly 'always-on' for capturing any call regardless of calendar status." A further structural note: "Google Meet flags third-party recording bots as a 'potential risk' by default as of March 2026" — a headwind specifically for bot-based tools, independent of the calendar-dependency question.

**Source:** WebSearch synthesis of multiple 2026 comparison articles (itsconvo.com, genesysgrowth.com, useluminix.com, aicentralresources.com); **UNVERIFIED** — this is a search-engine summary, not a page I directly fetched and confirmed a verbatim quote from. Flagging per citation discipline; treat as directionally corroborating, not as a sourced fact on its own.

**Significance:** On the specific axis the engineer cares about (auto-detect ANY call including Slack huddles, with no manual click), Shadow's documented claim is the closest match found to the literal desired workflow — closer than Granola's own detect-and-prompt model (Finding A1). Fathom's 2026 bot-free mode is architecturally similar to Granola (system-audio capture, no bot) but no source found confirms it auto-detects a Slack huddle specifically or removes the manual-start step; the TechCrunch source's stated differentiator is diarization quality, not detection automation.

### Finding F2 — A structurally different alternative class exists: continuous ambient-capture devices/apps (Limitless/Rewind), which record by default rather than by per-call detection

**Evidence:** "Limitless is the evolution of Rewind AI... a wearable 'Pendant' for in-person discussions, shifting the focus from visual screen recording to audio-based conversational intelligence... You can record all the time with the option to pause/stop recording when needed." Privacy design: "a 'consent mode,' which doesn't record the other person in the conversation unless they expressly agree to be recorded."

**Source:** WebSearch synthesis (skywork.ai, technowize.com, fastcompany.com, help.limitless.ai and others); **UNVERIFIED** — not directly fetched and quote-confirmed from a Limitless/Rewind primary source page.

**Significance:** This is a categorically different approach — continuous recording as the default state, with detection/segmentation happening after the fact, rather than Granola's per-call detect-and-prompt model. It removes the "did the tool notice this call" problem entirely, at the cost of a different privacy/consent posture and, for the Pendant, separate hardware. Not independently verified in this spike; flagged as a direction worth the engineer's own evaluation rather than a confirmed capability.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Rely on Granola's existing "call detected" notification (Finding A1) | Zero new tooling; already shipped; works for Slack, FaceTime, WhatsApp, "most platforms"; no calendar needed | Still requires a manual click on the notification — not silent/automatic; title still needs manual naming (Finding D1); no retroactive calendar re-link (Finding C2) | docs.granola.ai/help-center/taking-notes/notifications |
| Build glue automation around Granola (a macOS watcher that triggers the OS notification path, or that renames/relinks notes after the fact via the read-only API) | Keeps the engineer's existing tool, workflow, and historical note archive in Granola | Granola's API is read-only (Finding E1/E2) — there is no way to programmatically make Granola start capturing; Zapier is also read-only outbound (Finding E3); a watcher script could at most surface its own OS notification reminding the engineer to click "Take Notes" in Granola, duplicating what Granola's own notification already does | docs.granola.ai/introduction, docs.granola.ai/help-center/sharing/integrations/zapier |
| Switch to or add Shadow specifically for ad-hoc/huddle capture | Closest documented match to the literal desired workflow — auto-detects at the OS level with no manual click, explicitly including Slack Huddles (Finding F1) | A second tool alongside Granola (different note archive, different AI-enhancement quality/templates not evaluated in this spike); Mac-only; pricing not found in sources fetched | shadow.do (both articles) |
| Switch to or add Fathom's 2026 bot-free mode | Same general architecture as Granola (no bot, system-audio capture); adds speaker diarization Granola/Shadow may lack (per Fathom's own stated differentiator) | No source found confirming it solves the Slack-huddle-detection gap specifically (unlike Shadow); still a second tool / migration cost | techcrunch.com/2026/04/15 article |
| Continuous ambient capture (Limitless/Rewind) | Removes "did it notice the call" entirely — records by default | Structurally different privacy/consent model; separate hardware for the Pendant; not independently verified in this spike (UNVERIFIED sources only) | WebSearch synthesis only — not directly verified |

## What remains uncertain

- Whether Granola's "call detected" notification (Finding A1) can be configured to skip the click and start capturing fully silently — no source found describing such a setting; absence in documentation is not proof it doesn't exist as a hidden/enterprise-only toggle.
- The exact technical mechanism (ScreenCaptureKit specifics, permission model) Granola uses on macOS — flagged UNVERIFIED in Finding A2; would need a direct fetch of an engineering-level Granola source (none found in this spike) or the engineer's own inspection of the macOS permission prompt Granola triggers on first run.
- Whether Fathom's bot-free mode has its own equivalent of Granola's "call detected" notification for non-calendar apps like Slack huddles — the TechCrunch source did not address this, and no other source was found and fetched confirming or denying it.
- Shadow's and Limitless's actual pricing, team/enterprise fit, and data-retention/security posture — out of scope for the sources fetched in this time-boxed spike; would need direct research before either is adopted for team use (4Shark's own data-handling expectations were not evaluated against either tool here).
- Whether a macOS Shortcuts/Automator app-focus or process-watcher (detecting `Slack` entering a huddle state, or any app opening a call) could be built to at least auto-click Granola's own "Take Notes" notification button via UI scripting — not researched in this spike; would require accessibility-API-level automation research, which was out of scope for the questions as posed (the questions asked whether an API/webhook/URL-scheme surface exists for this, which was answered — Finding E1–E3 — but not whether OS-level UI automation of the notification button itself is feasible).

## Suggested options for main and the engineer

- **Option A — Use Granola's existing notification as-is.** No new tooling. Accept the one manual click per ad-hoc call (Finding A1), and continue manually naming ad-hoc notes (Finding D1) since no auto-rename exists. Lowest effort, smallest behavior change from today.
- **Option B — Add Shadow specifically for the ad-hoc/Slack-huddle gap, keep Granola for calendar meetings.** Two tools, split by use case: Granola for scheduled meetings (its stronger AI-note-templating ecosystem, per the reviews consulted, was not directly compared to Shadow's in this spike), Shadow for anything ad-hoc where true auto-detection matters (Finding F1). Requires evaluating Shadow's pricing, note-export format, and whether a fragmented note archive (two tools) is acceptable.
- **Option C — Evaluate Fathom's 2026 bot-free mode as a single-tool replacement for Granola.** If diarization quality or account-wide search (both claimed Fathom differentiators per the TechCrunch source) matter more than the Slack-huddle-specific auto-detection gap, a single-tool switch avoids the two-tool fragmentation of Option B — but this spike did not confirm Fathom solves the huddle-detection problem better than Granola's own notification.
- **Option D — Investigate OS-level UI automation of Granola's own notification button** (the open item in "What remains uncertain") as a build-the-glue path that keeps Granola as the sole tool. Not researched in this spike; would need a follow-up spike on macOS accessibility-API/UI-scripting feasibility specifically.

No recommendation is made among these — the trade-offs (tool fragmentation vs. automation feasibility vs. accepting the one-click friction) are the engineer's call.
