Compiled verbatim quotes fetched during research, one block per source, kept
here so a future revision of SPIKE.md can re-weight or drop a source without
re-fetching. Each block names the URL and the fetch date.

---

## cli.github.com/manual/gh_help_environment (fetched 2026-08-03)

> "`GH_BROWSER`, `BROWSER` (in order of precedence): the web browser to use
> for opening links."

---

## cli.github.com/manual/gh_config (fetched 2026-08-03)

Respected settings list includes:

> `browser`: "the web browser to use for opening URLs"

Full list also includes `git_protocol`, `editor`, `prompt`,
`prefer_editor_prompt`, `pager`, `http_unix_socket`, `color_labels`,
`accessible_colors`, `accessible_prompter`, `spinner`, `telemetry`.

---

## cli.github.com/manual/gh_pr_create (fetched 2026-08-03)

`-w`, `--web` flag description:

> "Open the web browser to create a pull request"

Default (no `--web`):

> "the URL of the created pull request will be printed"

---

## cli.github.com/manual/gh_pr_view (fetched 2026-08-03)

`-w`, `--web` flag description:

> "Open a pull request in the browser"

Default (no `--web`):

> "Display the title, body, and other information about a pull request"
> ... "Without an argument, the pull request that belongs to the current
> branch is displayed."

---

## cli.github.com/manual/gh_browse (fetched 2026-08-03)

> "Transition from the terminal to the web browser to view and interact
> with: Issues, Pull requests, Repository content, Repository home page,
> Repository settings"

Default behavior: opens the browser to display the requested resource.

`-n, --no-browser` flag:

> prints the destination URL instead of opening the browser

---

## developer.apple.com/forums/thread/739524 — "NSRunningApplication
## activateWithOptions does not work on Sonoma" (fetched 2026-08-03)

> "NSApplicationActivateIgnoringOtherApps is deprecated in Sonoma so it
> seems intentional."

> "I use NSApplication +activateIgnoringOtherApps: to workaround some bugs
> in macOS before...but that's also deprecated and I haven't tested but I
> assume that that method doesn't work either anymore."

Also notes `NSApplicationActivateAllWindows` has not worked since at least
macOS 10.15, workaround being the deprecated Carbon function
`SetFrontProcessWithOptions`.

---

## furnacecreek.org/blog/2024-04-14-how-to-prevent-background-mac-app-store-rating-windows
## (fetched 2026-08-03)

> Apple introduced new cooperative activation functionality in macOS
> Sonoma. According to the documentation, "activation is now a request,
> not a command" instead of apps being able to steal focus.

> "Under the new cooperative activation model, AppKit prevents this
> process from stealing focus—which inadvertently causes the rating
> window to appear in the background."

Workaround code shown:
```swift
if #available(macOS 14.0, *) {
    NSApp.yieldActivation(toApplicationWithBundleIdentifier:
        "com.apple.storeuid")
}
```

---

## holgr.com/blog/macos-sonoma-theres-a-process-stealing-your-window-focus/
## (fetched 2026-08-03)

> "the window I am working in will sometimes lose focus (without the app
> losing focus)"

> Apple's own `CoreServicesUIAgent` is the problem (per the author's
> diagnostic script `find_focus_stealer.py`), though the author suspects
> an underlying macOS bug.

> July 2024 update: "Ever since removing Carrot Weather from my Mac this
> issue has gone away."

---

## developer.apple.com/forums/thread/807805 — "Activating application from
## Terminal occasionally fails on macOS 26" (fetched 2026-08-03)

Original poster (1024jp):

> "On macOS Tahoe 26 activating GUI apps from command-line often fails. It
> launches the app but not brings to the foreground as expected."

> "These commands worked as expected until macOS 15 but no more in macOS
> 26."

> "The tricky part is that this failure doesn't happen 100% of the time;
> it occurs randomly. However, since multiple users of my app have
> reported the same symptoms, and I can reproduce it not only with my app
> but also with apps bundled to macOS, I don't believe this is an issue
> specific to my environment alone."

> "Moreover, they sometimes not return in Terminal."

Commands cited as affected: `open /Applications/Pages.app` and
`osascript -e 'tell application "Pages" to activate'`.

DTS Engineer Quinn's reply:

> "This is likely fallout from a general effort to stop apps stealing
> focus from other apps."

---

## macos-defaults.com/mission-control/applespacesswitchonactivate.html
## (fetched 2026-08-03)

> Description: "When switching to an app, switch to a space with open
> windows for this app."

> Command: `defaults write NSGlobalDomain "AppleSpacesSwitchOnActivate"
> -bool "true"`

---

## talk.macpowerusers.com — "Is there a way to prevent applications from
## stealing focus when they startup on macOS?" (fetched 2026-08-03)

Login Items method: a user recommends using Login Items with a "Hide"
option that "tell[s] the app to NOT steal focus."

Command-line method:

> `open -j -a AppName` — launches completely hidden
> `open -g -a AppName` — launches visible but in background
> `"open -g -a TextEdit"` will "Launch the App Visible, But in the
> Background"

AppleScript / Excel example given by a user:

> `do shell script "open -g \"/Applications/Microsoft Excel.app\""`
> `tell me to quit`

Caveat from a developer in the same thread:

> "Yes…_if_ the app is built by a Mac developer who knows what they are
> doing."

No mention of a system-wide toggle, and no mention of Hammerspoon,
BetterTouchTool, or Karabiner-Elements in this thread.

---

## forums.macrumors.com — "Way to disable apps taking over focus?"
## (fetched 2026-08-03)

Summary (paraphrase, no direct quote extracted): no built-in solution
found in the thread; suggestions were Spaces-per-app, finishing work
before launching, full-screen mode, and clicking the Dock icon to
return. The original poster's request for a native toggle went
unanswered.

---

## en.wikipedia.org/wiki/Focus_stealing (fetched 2026-08-03)

> "Focus stealing is a mode error occurring when a program not in focus
> places a window in the foreground and redirects all keyboard input to
> that window."

> Older Windows versions had a user setting to prevent focus stealing,
> but it "does not work in Windows 7 or later."

---

## hammerspoon.org/docs/hs.application.watcher.html (fetched 2026-08-03)

`activated` event constant:

> "An application has been activated (i.e. given keyboard/mouse focus)"

Full constant list: `launching`, `launched`, `terminated`, `hidden`,
`activated`, `deactivated`, `unhidden`.

---

## brettterpstra.com/2014/08/06/shell-tricks-the-os-x-open-command/
## (fetched 2026-08-03)

> "The `-g` flag is another handy one. It will open the target
> application in the background, so it doesn't steal window focus."

Context given: useful with iTerm2 visor mode so the terminal window
doesn't lose focus when `open`-ing a link.
