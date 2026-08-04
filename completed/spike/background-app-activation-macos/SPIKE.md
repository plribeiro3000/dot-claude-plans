# SPIKE — Background App Activation on macOS (Focus-Stealing from Parallel Claude Code Sessions)

## Outcome

No mechanism reachable from the command line avoids the window raise — see
Finding 10, which measures every candidate against keyboard focus AND against
window layering, and finds that only the second one matters. Option (c) below
(generalizing the rewrite to every `open`) was therefore not taken.

What shipped instead is the rule that an artifact is delivered as a PATH and
opened only when the engineer explicitly asks for it, reinforced by
`scripts/inject-no-auto-open-context.sh` — an injector rather than a block,
because "did the engineer ask for this?" is judgment a hook cannot decide.
The rule lives in `CLAUDE.md` § Output Policy, Layer 2.

**Orientation for the code references below**: this document analyses
`validate-html-open.sh`, the `.html`-scoped hook that occupied that slot while
this research ran. That file is gone and `inject-no-auto-open-context.sh`
occupies the slot now, so its line references resolve against git history
rather than the working tree. The analysis of what it did and why its scope
was too narrow is still what motivates the replacement.

## Investigation question

The engineer runs roughly 11 parallel Claude Code sessions (native desktop app,
`CLAUDE_CODE_ENTRYPOINT=claude-desktop`) on one macOS machine. Sessions
routinely produce side effects that raise a different application in front of
the engineer — opening a PR (Chrome), opening a generated HTML report
(Chrome), opening a generated `.xlsx` (Excel) — which yanks focus away from
whatever session the engineer is reading, several times an hour.

Questions to settle:

1. Does a global, system-wide macOS setting exist that makes ALL apps
   launch/open without activating?
2. What do `open(1)`'s `-g`, `-j`, `-n` flags actually guarantee, and does
   that guarantee survive an app that self-activates? What changed in macOS
   14 Sonoma's cooperative activation model, and does it help here?
3. Does the Mission Control "switch to a Space with open windows" setting
   change anything for this workflow?
4. What do third-party focus guards (Hammerspoon, BetterTouchTool,
   Karabiner-Elements) actually offer, and what are their failure modes?
5. What issues the focus-stealing calls in this specific setup — `gh pr
   create --web` / `gh pr view --web` / `gh browse`, and `open <file>.xlsx`
   — and can each be told not to?
6. Is generalizing the existing `validate-html-open.sh` rewrite (currently
   scoped to `.html`/`.htm`) to every `open` invocation sound, and what
   shapes would it need to cover?

## Sources consulted

- `man open` (local, macOS 26.5.2 on this machine) — see auxiliary
  `background-app-activation-macos_doc_1.txt`, the exact flag set and
  wording this machine ships.
- `~/.claude/scripts/validate-html-open.sh:88-152` — the existing hook that
  already solves this problem for `.html` only.
- [cli.github.com/manual/gh_help_environment](https://cli.github.com/manual/gh_help_environment) — `BROWSER`/`GH_BROWSER` precedence.
- [cli.github.com/manual/gh_config](https://cli.github.com/manual/gh_config) — the `browser` config key.
- [cli.github.com/manual/gh_pr_create](https://cli.github.com/manual/gh_pr_create) — default (no `--web`) behavior.
- [cli.github.com/manual/gh_pr_view](https://cli.github.com/manual/gh_pr_view) — `--web` is opt-in.
- [cli.github.com/manual/gh_browse](https://cli.github.com/manual/gh_browse) — opens by default; `-n/--no-browser` prints instead.
- [developer.apple.com/forums/thread/739524](https://developer.apple.com/forums/thread/739524) — `activate(ignoringOtherApps:)` deprecation confirmed by community, on Sonoma.
- [furnacecreek.org blog post on cooperative activation](https://furnacecreek.org/blog/2024-04-14-how-to-prevent-background-mac-app-store-rating-windows) — "activation is now a request, not a command."
- [holgr.com blog post on a Sonoma focus-stealing bug](https://holgr.com/blog/macos-sonoma-theres-a-process-stealing-your-window-focus/) — a documented case of *unwanted* loss of focus, opposite direction but same underlying activation machinery.
- [developer.apple.com/forums/thread/807805](https://developer.apple.com/forums/thread/807805) — `open` failing to foreground an app is reported as an active, intermittent bug on macOS 26 (Tahoe), the version family this machine runs.
- [macos-defaults.com — AppleSpacesSwitchOnActivate](https://macos-defaults.com/mission-control/applespacesswitchonactivate.html) — the Mission Control "switch to Space" default.
- [talk.macpowerusers.com thread on preventing focus stealing](https://talk.macpowerusers.com/t/is-there-a-way-to-prevent-applications-from-stealing-focus-when-they-startup-on-macos/24539) — community consensus: no system-wide toggle; `open -g`/`-j` per-invocation; a concrete Excel example.
- [forums.macrumors.com — "Way to disable apps taking over focus?"](https://forums.macrumors.com/threads/way-to-disable-apps-taking-over-focus.2340484/) — same negative finding from a second, independent community.
- [en.wikipedia.org/wiki/Focus_stealing](https://en.wikipedia.org/wiki/Focus_stealing) — the established term and definition.
- [hammerspoon.org/docs/hs.application.watcher.html](https://www.hammerspoon.org/docs/hs.application.watcher.html) — the `activated` event primitive a guard-side fix would use.
- [brettterpstra.com — Shell tricks: the OS X open command](https://brettterpstra.com/2014/08/06/shell-tricks-the-os-x-open-command/) — independent confirmation of what `-g` does.
- See auxiliary: `background-app-activation-macos_notes_1.md` — every verbatim quote gathered above, compiled with URL and fetch date, so a revision pass does not need to re-fetch.
- See auxiliary: `background-app-activation-macos_doc_1.txt` — the raw local `man open` output.
- See auxiliary: `background-app-activation-macos_log_1.txt` — the raw local `sw_vers` output (macOS 26.5.2, build 25F84).

## Findings

### Finding 1: No global, system-wide "open everything in the background" setting exists

**Evidence:** Two independent community threads asked exactly this question
and neither surfaced a system-wide toggle. From the MacRumors thread: no
built-in solution was found; suggestions were confined to per-app
workarounds (Spaces, full-screen, clicking the Dock icon). From the
MacPowerUsers thread, the closest thing offered was the per-app Login Items
"Hide" option and the per-invocation `open -g`/`open -j` flags — not a
system-wide switch.

**Source:** [talk.macpowerusers.com](https://talk.macpowerusers.com/t/is-there-a-way-to-prevent-applications-from-stealing-focus-when-they-startup-on-macos/24539) (fetched 2026-08-03), [forums.macrumors.com](https://forums.macrumors.com/threads/way-to-disable-apps-taking-over-focus.2340484/) (fetched 2026-08-03).

**Significance:** The engineer's hypothesis — "there is probably an OS-level
setting to make every application always open in the background" — is not
supported by either source consulted. No Apple support document, MDM
payload, or `defaults` key surfaced in this research that does this
globally. This is a negative finding, not an absence of search effort: two
independent community threads asked the identical question and both came up
empty. **Not found**: a global toggle. If one exists, it was not found by
this research and no source claims one exists.

### Finding 2: `open -g` / `-j` are per-invocation flags, not a global setting, and only control what `open` itself does — not what the launched app does afterward

**Evidence:** the local man page (macOS 26.5.2, this machine):

```
     --gg  Do not bring the application to the foreground.

     --jj  Launches the app hidden.
```

There is no long-form `--background` or `--hide` spelling in this machine's
man page — only the short flags `-g` and `-j` are documented locally.

**Source:** `background-app-activation-macos_doc_1.txt` (local `man open`,
lines 61 and 63).

**Significance:** `validate-html-open.sh:105` matches `-g|--background|-j|--hide`
as synonyms, but the long forms are not documented in this machine's man
page — an internal-consistency note for that script (whether the long forms
work in practice on this macOS version was not verified in this research;
only the man-page text was checked).

The flags are correct as far as they go — `-g` tells `open` itself not to
foreground the target app — but neither flag prevents the *launched
application's own code* from calling an activation API once it is running.

### Finding 3: `-g`'s guarantee does not survive an app that self-activates

**Evidence:** community search summary states the mechanism plainly — "The
`-g` flag controls whether the `open` command itself brings the app to the
foreground, but it cannot prevent the application itself from activating
after it launches." This is corroborated by a direct, dated developer-forum
report of the opposite failure — `open` sometimes *fails* to foreground an
app it should, which only makes sense if activation now happens through a
separate, app-mediated request rather than a guarantee `open` itself
controls:

> "On macOS Tahoe 26 activating GUI apps from command-line often fails. It
> launches the app but not brings to the foreground as expected." ...
> "This is likely fallout from a general effort to stop apps stealing focus
> from other apps." (Apple DTS engineer reply)

**Source:** [developer.apple.com/forums/thread/807805](https://developer.apple.com/forums/thread/807805) (fetched 2026-08-03, quotes from the original poster and DTS engineer "Quinn").

**Significance:** this is a **two-sided** risk for the engineer's workflow.
On one hand, an app that calls its own activation API (pre-Sonoma pattern,
still present in many third-party apps including likely Chrome/Excel) can
override `open -g` and foreground itself regardless of the flag — this is
the failure the engineer is fighting. On the other hand, this same
machine's OS version family (26.x / Tahoe) has an independently reported,
Apple-acknowledged intermittent bug where `open` (even without `-g`) simply
fails to foreground an app at all. Neither direction is fully deterministic
on this OS version as of this research.

### Finding 4: macOS 14 Sonoma's cooperative activation model changed the default from "any app can force focus" to "activation is a request the current app can refuse" — but this is a change to *unsolicited/OS-mediated* activation, not a new user-facing switch

**Evidence:**

> "Sonoma made changes to the app activation process designed to prevent one
> app from stealing focus from each other" ... "activation is now a
> request, not a command" ... "The system now dynamically determines
> whether to grant activation based on context."

> "NSApplicationActivateIgnoringOtherApps is deprecated in Sonoma so it
> seems intentional."

**Source:** [furnacecreek.org](https://furnacecreek.org/blog/2024-04-14-how-to-prevent-background-mac-app-store-rating-windows) (fetched 2026-08-03), corroborated by [developer.apple.com/forums/thread/739524](https://developer.apple.com/forums/thread/739524) (fetched 2026-08-03).

**Significance:** this is the closest thing to "Apple restricted
focus-stealing" that this research found, and it is real — but it governs
how *apps* are supposed to request activation of *other* apps
programmatically (`NSRunningApplication.activate` + `yieldActivation`), not
whether an app that launches itself (e.g. Chrome opening because `open` or
`gh browse` targeted it, or Excel opening because the file's default handler
is Excel) will foreground itself. Cooperative activation constrains
app-to-app activation *requests*; it does not appear to touch the base case
of "the user (or a script acting for the user) opened a file/URL, and the
app that owns that file/URL type activates on launch," which is the
mechanism behind the engineer's problem. **This is inference from the
sourced material, not a direct claim any source makes about this specific
scenario** — flagged as uncertain in "What remains uncertain" below.

### Finding 5: the Mission Control "switch to Space with open windows" setting is orthogonal — it changes which Space you land on, not whether the app activates

**Evidence:**

> Description: "When switching to an app, switch to a space with open
> windows for this app."
> Command: `defaults write NSGlobalDomain "AppleSpacesSwitchOnActivate" -bool "true"`

**Source:** [macos-defaults.com](https://macos-defaults.com/mission-control/applespacesswitchonactivate.html) (fetched 2026-08-03).

**Significance:** this setting only matters once an app has already been
activated by some other action (a click, a Cmd-Tab, or a launch) and that
app has a window on a different Space — it decides whether the Mac's
visible desktop follows you there. It does not stop the activation from
happening in the first place. Turning it **off** would mean a
self-activating Chrome/Excel steals keyboard/mouse focus without visibly
switching the Space (the window opens off-screen, on whatever Space it was
last on) — which could reduce the *visual* jarring but the engineer would
still lose keyboard focus to it. Putting Claude Code on a dedicated Space
does not prevent a new window belonging to another app on a *different*
Space from still taking activation; whether the desktop visibly follows
depends on this exact setting, which is the closest description this
research found for that interaction. **No source directly tested "does a
new window on another Space still yank focus with this setting off"** —
this is reasoned from the setting's own description, not a tested or
sourced empirical claim.

### Finding 6: third-party focus guards exist as primitives (Hammerspoon), but no turnkey "pin focus to app X" script was found published and citable

**Evidence:** Hammerspoon's `hs.application.watcher` exposes exactly the
event needed to detect an unwanted activation:

> `activated` — "An application has been activated (i.e. given
> keyboard/mouse focus)"

**Source:** [hammerspoon.org/docs/hs.application.watcher.html](https://www.hammerspoon.org/docs/hs.application.watcher.html) (fetched 2026-08-03).

**Significance:** a guard-side fix ("let it activate, then bounce focus
back") is buildable from this primitive — subscribe to `activated`, check
whether the newly-activated app is on an allowlist/denylist, and if not,
call `hs.application.get("Claude"):activate()` (or equivalent) to hand
focus back. This research did **not** find a published, complete example of
this exact "refocus on unexpected activation" pattern to cite directly —
the closest hit (`mskelton.dev`) uses `hs.window.filter` for a different
purpose (toggling macOS Focus/DND mode on Zoom meeting windows, not
window-focus arbitration). **Not found**: a citable, working "refocus
pinned app" Hammerspoon script. The primitive exists and is documented; the
finished recipe was not found in this research.

For BetterTouchTool and Karabiner-Elements specifically: **not found**.
Neither tool's own documentation or community discussion surfaced in this
search describes a focus-stealing-prevention capability. Karabiner-Elements
is a keyboard remapper; BetterTouchTool is gesture/window-snapping focused.
Absence of evidence is not evidence of absence here — this reflects what
this search turned up, not an exhaustive audit of either tool's full
feature set.

Known failure modes of the watcher approach, reasoned from the API shape
rather than sourced from an incident report: a watcher that unconditionally
bounces focus back would fight the engineer's own deliberate Cmd-Tab to
Chrome/Excel (a real switch looks identical, in-band, to an "unwanted"
activation — the watcher cannot tell intent apart from a timestamp alone),
and `hs.application.watcher` requires the Accessibility permission grant to
function at all. Neither of these is drawn from a cited source; they follow
directly from what the `activated` event does and does not tell the
subscriber (an app name and an event type — no signal for user-intent).

### Finding 7: the GitHub CLI family used in this repo's workflow does NOT open a browser by default — the risk is opt-in flags and `gh browse`

**Evidence:**

> `gh pr create` `-w`/`--web`: "Open the web browser to create a pull
> request." Default (no `--web`): "the URL of the created pull request will
> be printed."

> `gh pr view` `-w`/`--web`: "Open a pull request in the browser." Default:
> displays title/body/info in the terminal.

> `gh browse`: "Transition from the terminal to the web browser to view and
> interact with: Issues, Pull requests, Repository content, Repository home
> page, Repository settings" — opens by default; `-n`/`--no-browser` "prints
> the destination URL instead of opening the browser."

**Source:** [cli.github.com/manual/gh_pr_create](https://cli.github.com/manual/gh_pr_create), [cli.github.com/manual/gh_pr_view](https://cli.github.com/manual/gh_pr_view), [cli.github.com/manual/gh_browse](https://cli.github.com/manual/gh_browse) (all fetched 2026-08-03).

**Significance:** this repo's own PR-creation convention (CLAUDE.md § "Creating
pull requests") already calls `gh pr create --title ... --body ...` with no
`--web` flag — so, per this documentation, that specific invocation does not
open a browser today; it prints the URL. The place a browser tab genuinely
opens by default is `gh browse` (no flags) or any explicit `--web` on `gh pr
create`/`gh pr view`. If the engineer's "opening a PR" side effect is
happening, either (a) a session is passing `--web` somewhere, (b) a session
is running `gh browse` to show the PR, or (c) a session is separately
running a bare `open <pr-url>` after `gh pr create` printed the link — (c)
is plausible because nothing in this repo's tooling currently gates a raw
`open <non-html-url>` call (see Finding 9).

**Verification block:** URL fetched: yes, three URLs. Verbatim quote
checked: yes. Quote substring confirmed at: the `--web` flag description
line and the "will be printed" / "no browser" default-behavior sections of
each respective manual page as rendered.

### Finding 8: for `gh`, there IS a documented, config-level way to redirect or suppress the browser — via the `browser` config key and the `BROWSER`/`GH_BROWSER` environment variables

**Evidence:**

> "`GH_BROWSER`, `BROWSER` (in order of precedence): the web browser to use
> for opening links."

> `gh config set` respected settings include `browser`: "the web browser to
> use for opening URLs."

**Source:** [cli.github.com/manual/gh_help_environment](https://cli.github.com/manual/gh_help_environment), [cli.github.com/manual/gh_config](https://cli.github.com/manual/gh_config) (both fetched 2026-08-03).

**Significance:** the documentation confirms `gh` reads a **browser to use**,
not a **whether-to-open-a-browser** toggle — both the env vars and the
config key are described as selecting *which* browser, not suppressing the
open. A community GitHub issue (search-summarized, not independently
verified by direct fetch) suggests setting `BROWSER=none` produces an error
rather than a graceful skip — this claim is **UNVERIFIED**: it came from
the WebSearch tool's own summary of [github.com/cli/cli/issues/858](https://github.com/cli/cli/issues/858), not from a quote this research
independently confirmed by fetching the issue page (the direct fetch of
that issue returned no comment content). Do not treat "`BROWSER=none`
errors gracefully-skips" as confirmed.

The safer, confirmed lever is simply not passing `--web` and not calling `gh
browse` — which, per Finding 7, is already this repo's documented PR-creation
pattern.

**Verification block:** URL fetched: yes. Verbatim quote checked: yes for
the `GH_BROWSER`/`BROWSER` precedence line and the `browser` config-key
line. The `BROWSER=none` claim is explicitly marked UNVERIFIED and excluded
from any derivation below.

### Finding 9: the repo's existing mechanical fix (`validate-html-open.sh`) is scoped narrowly to `.html`/`.htm` — every other focus-stealing shape in the engineer's report is currently unguarded

**Evidence:**

```bash
# ~/.claude/scripts/validate-html-open.sh:100-106
html_path=""
already_backgrounded="false"

for token in "${tokens[@]}"; do
    case "$token" in
        -g|--background|-j|--hide) already_backgrounded="true" ;;
        *.html|*.htm) html_path="$token" ;;
    esac
done
```

```bash
# ~/.claude/scripts/validate-html-open.sh:93
if [ "$first_token" != "open" ]; then
    exit 0
fi
```

**Source:** `~/.claude/scripts/validate-html-open.sh:93, 100-106` (read
directly from this machine's installed config, verbatim).

**Significance:** the hook only fires when (a) the command's first token is
literally `open`, and (b) one of the tokens ends in `.html`/`.htm`. This
means: `open report.xlsx`, `open https://github.com/.../pull/123`, `open -a
"Microsoft Excel" report.xlsx`, and `gh pr create --web` / `gh browse` all
fall completely outside this hook's coverage today — none of them is `open
<something>.html`. The hook also explicitly defers (its own header comment,
lines 45-46) on any compound/piped/subshell command and on any quoted
argument — so `open -a "Microsoft Excel" file.xlsx` (a quoted app name) is a
shape the *current* hook would defer on even if its scope were widened
verbatim, because of the existing quote-defer rule at
`validate-html-open.sh` (search: `*'"'*|*"'"*) exit 0 ;;`).

### Finding 10: keyboard focus and window layering are separate properties, and only the second one is the disruption — measured directly on this machine

**Evidence:** direct measurement on this machine (macOS 26.5.2), taking
`lsappinfo front` before and after each invocation and resolving the returned
ASN with `lsappinfo info -only name`:

| Invocation | Frontmost application after | Window raised |
|---|---|---|
| `open -g <file>.html` (Chrome not running) | Google Chrome | yes |
| `open -g <file>.html` (Chrome already running) | Google Chrome | yes |
| `open -g -a "Microsoft Excel" <file>.csv` | Claude (unchanged, two samples) | not observed |
| `osascript -e 'tell application "Google Chrome" to open location "..."'` | Claude (unchanged) | **yes** |

The AppleScript row is the load-bearing one. The tab opened (confirmed by
reading back `URL of active tab of front window`) and the frontmost
application never changed — yet the engineer, watching the screen, reported
the window still came forward.

**Source:** local measurement, not a fetched source. `lsappinfo` is
`/usr/bin/lsappinfo`; `man open` for this machine is preserved in
`background-app-activation-macos_doc_1.txt`.

**Significance:** `lsappinfo front` reports the frontmost APPLICATION, which
is keyboard focus. An application can raise a window over the current one
without becoming frontmost, so a test that measures only the frontmost
application reports success for an approach that visibly fails. This is the
trap that makes Finding 3's `-g` question look answerable from the command
line when it is not: **any evaluation of a "background open" mechanism needs
a window-layering check, or a human watching the screen — never a focus
check alone.**

The practical consequence is that options (b), (c) and (d) below all inherit
this constraint: none of them was shown to avoid the raise, and (c) in
particular cannot be validated by the obvious scripted test.

## Trade-offs surfaced

| Approach | What it fixes | What it does NOT fix | Effort | Enforceable mechanically? |
|---|---|---|---|---|
| Search for a global macOS "open everything in background" setting | — | Nothing — not found to exist (Finding 1) | N/A | N/A |
| `open -g` / `open -j` per invocation | Keyboard focus for a document handled by a non-browser application — Excel held it under `-g` (Finding 10) | The WINDOW raise, which is the actual disruption (Finding 10); Chrome, which defeats `-g` entirely, cold and warm alike (Finding 10); an app that self-activates via its own code once launched (Finding 3) | Low | Yes, per-command — but it does not deliver what the workflow needs |
| Rely on macOS 14+ cooperative activation | Reduces unsolicited app-to-app activation requests going forward (system apps built against the new API) | Does not appear to change the base "user/script opened a file or URL, owning app activates on launch" case this workflow hits (Finding 4, inference flagged as uncertain) | None — already active on this OS version | No — it's OS behavior, not something 4Shark configures |
| Mission Control "switch to Space with open windows" OFF, dedicated Space for Claude Code | May reduce the *visual* jump (desktop does not follow) | Does not stop the activation/focus-steal itself (Finding 5) | Low (one `defaults write` + a `killall Dock`) | No — a system preference, not gated by any hook |
| Stop issuing the activating call — `gh pr create` without `--web`, no `gh browse`, `gh pr view` without `--web` | The GitHub-side opens entirely, when the only calls used are the no-`--web` default forms (Finding 7) | Anything a bare `open <url>` or `open <file>.xlsx` still does after `gh` prints the link (Finding 9) | Low — this repo's PR convention already omits `--web` | Partially — a hook could block `--web`/`gh browse` the way `validate-html-open.sh` blocks `open *.html`, but none currently does |
| Generalize `validate-html-open.sh`'s rewrite to every `open` invocation (any file type, any URL) | `open report.xlsx`, `open <url>` — the two shapes Finding 9 shows are currently unguarded | An app that self-activates after launch regardless of `-g` (Finding 3); `open -a "App" file` shapes with a quoted app name, which the existing hook's own quote-defer rule would skip (Finding 9) | Low-medium — mostly extending the existing `case` pattern match and dropping the `.html`/`.htm` restriction | Yes — same mechanism already proven for `.html` |
| Hammerspoon `hs.application.watcher` guard — bounce focus back to Claude Code on unwanted activation | Would catch any app that does self-activate, regardless of what issued the call (`gh`, Excel, Chrome, anything) | Fights the engineer's own deliberate Cmd-Tab (Finding 6) unless intent is somehow distinguished — no sourced example does this; needs Accessibility permission | Medium-high — no citable, complete example found (Finding 6); would be custom-built | Yes, but depends on discipline in writing correct intent-detection logic, which is unproven here |

## What remains uncertain

- Whether macOS 14+ cooperative activation actually applies to the "file/URL
  opened, default-handler app activates on launch" case at all, or only to
  explicit app-to-app activation requests (`NSRunningApplication.activate`)
  — **inferred, not confirmed by a source that addresses this specific
  scenario** (Finding 4).
- Whether a window-layering-aware approach exists at all on macOS 26 — every
  mechanism reachable from the command line was measured against keyboard
  focus AND against the engineer watching the screen (Finding 10), and all of
  them raise the window. Whether some Chrome-specific AppleScript form (for
  example creating a tab in an existing window rather than `open location`)
  avoids the raise was not tested.
- Whether `BROWSER=none` (or `GH_BROWSER=none`) causes `gh` to error loudly
  or silently skip opening — explicitly UNVERIFIED (Finding 8).
- Whether the intermittent macOS 26 "activation sometimes fails" bug
  (Finding 3) would, if it also affects `open -g`, make the guard-rewrite
  approach (Finding 9's proposed generalization) unreliable in the opposite
  direction — sometimes failing to open the file/URL at all. Not tested.
- No complete, citable Hammerspoon (or other tool) script implementing
  "pin focus to app X unless the user deliberately switched" was found
  (Finding 6) — only the primitive event (`activated`) that such a script
  would be built on.
- What exactly issues the `.xlsx`-opening `open` call today in this
  workflow — no skill or doc in this repo's `~/.claude/skills`, `docs`, or
  `scripts` was found mandating an `open` for a generated `.xlsx` (a search
  across those directories found no such instruction), so this is
  presumably an ad hoc choice made per-session, not a documented pattern.

## Suggested options for main and the engineer

Ranked by how directly each addresses the reported symptom, not by
recommendation (per the subagent contract, no option is endorsed over
another):

**(a) OS-level settings — verified NOT to exist as a global switch; do not
pursue further under this framing.** Finding 1 is a negative but complete
answer to the engineer's stated hypothesis: no source found supports a
system-wide "open in background" toggle, `defaults` key, or MDM payload.
The Mission Control Space-switch setting (Finding 5) is real but changes
visual behavior, not activation itself.

**(b) Source-side fixes — stop issuing the activating call:**
- Confirm no session ever passes `--web` to `gh pr create`/`gh pr view`, and
  never calls `gh browse` — per Finding 7, the documented default behavior
  of the exact commands this repo already uses does not open a browser.
- What fixes: entirely eliminates the GitHub-triggered browser opens, IF
  those are in fact the source (unconfirmed which command is actually
  firing — Finding 9 flags this as unverified in this research).
- What it does not fix: the `.xlsx`/Excel case, and any other ad hoc `open`
  call a session issues on its own initiative.
- Effort: low. Enforceable mechanically: yes, the same shape as
  `validate-html-open.sh` could block a `--web` flag or a bare `gh browse`
  the way it blocks `open *.html`.

**(c) Generalize `validate-html-open.sh`'s rewrite to every `open`
invocation, any file type, any URL (Finding 9):**
- What fixes: `open report.xlsx`, `open <pr-url>`, and any future file type
  a session decides to `open` — all currently unguarded.
- What it does not fix: an app that self-activates internally after launch
  regardless of `-g` (Finding 3) — this remains a discipline/best-effort
  gap, same as it is today for `.html` on non-desktop entrypoints.
- Shapes it would need to handle, enumerated per the engineer's question:
  `open <file>` (any extension), `open <url>`, `open -a <App> <file>` (the
  existing hook already defers on this because of its quote-detection rule
  when `<App>` has a space — would need explicit handling, not silent
  deferral, to actually cover this shape), `gh ... --web` / `gh browse`
  (different binary, would need a second hook or an extended matcher), and
  any `xdg-open`-equivalent (not applicable on macOS — out of scope here).
- Effort: low-medium (mostly widening an existing, already-proven `case`
  pattern).
- Enforceable mechanically: yes — this is the same class of fix already in
  production for `.html`.

**(d) Guard-side fix — Hammerspoon watcher that bounces focus back to
Claude Code on an unexpected activation (Finding 6):**
- What fixes: any focus steal regardless of source, including a
  self-activating app that defeats `-g`.
- What it does not fix, by construction: distinguishing the engineer's own
  deliberate Cmd-Tab from an unwanted activation — no sourced example
  solves this, and it is a real design problem for this approach, not
  merely an implementation detail.
- Effort: medium-high — no turnkey script was found; would be built from
  scratch using the documented `hs.application.watcher` `activated` event
  primitive, and would need an Accessibility permission grant.
- Enforceable mechanically: yes once built, but its correctness (not
  fighting deliberate switches) is unproven and would need to be validated
  empirically on this machine before trusting it.

**(e) Mission Control containment — dedicated Space for Claude Code,
`AppleSpacesSwitchOnActivate` off (Finding 5):**
- What fixes: possibly softens the visual jarring of a Space switch.
- What it does not fix: the actual focus/keyboard steal — the new window
  still takes activation, per every source consulted; only whether the
  visible desktop follows it is what this setting controls.
- Effort: trivial (one `defaults write`).
- Enforceable mechanically: no — a system preference outside any hook's
  reach, and its effect on the underlying problem is the weakest of the
  options above.
