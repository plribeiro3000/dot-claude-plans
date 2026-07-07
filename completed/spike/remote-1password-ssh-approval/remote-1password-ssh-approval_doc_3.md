# Auxiliary source — Claude Code official docs: Remote Control

- URL: https://code.claude.com/docs/en/remote-control
- Fetched: 2026-07-06 (full page, not persisted separately — under the tool's size-persistence threshold; reproduced here for citation integrity)

> Remote Control connects claude.ai/code or the Claude app for iOS and Android to a Claude Code session running on your machine. Start a task at your desk, then pick it up from your phone on the couch or a browser on another computer.

> When you start a Remote Control session on your machine, Claude keeps running locally the entire time, so nothing moves to the cloud.

> Use your full local environment remotely: your filesystem, MCP servers, tools, and project configuration all stay available, and typing `@` autocompletes file paths from your local project

> Unlike Claude Code on the web, which runs on cloud infrastructure, Remote Control sessions run directly on your machine and interact with your local filesystem. The web and mobile interfaces are just a window into that local session.

## Connection and security

> Your local Claude Code session makes outbound HTTPS requests only and never opens inbound ports on your machine. When you start Remote Control, it registers with the Anthropic API and polls for work. When you connect from another device, the server routes messages between the web or mobile client and your local session over a streaming connection.

> All traffic travels through the Anthropic API over TLS, the same transport security as any Claude Code session. The connection uses multiple short-lived credentials, each scoped to a single purpose and expiring independently.

## Trusted Devices (a distinct, unrelated control plane)

> Trusted Devices is an organization-wide setting that requires members to verify their device before they can view or steer Remote Control sessions from claude.ai, the Claude mobile apps, or Claude Desktop. It ties Remote Control access to a known device and a recent authentication, not just a signed-in account.

> An enrolled device: each browser, phone, or desktop app a member uses for Remote Control enrolls its own credential. Enrollment is only offered shortly after a full sign-in, so a device joins the trusted list as part of a real authentication rather than silently in the background.

> A recent sign-in: the member's sign-in must be no more than 18 hours old. Instead of signing in again each day, members confirm presence with Face ID, Touch ID, Windows Hello, or a passkey. This biometric step-up refreshes the session immediately.

> Biometric checks run on the device through the operating system or browser, the same mechanism as passkey sign-in. Anthropic never receives or stores fingerprints, face data, or any other biometric information. Only the device's public key and basic metadata such as display name, platform, and enrollment time are stored.

> The setting applies only to Remote Control. Regular Claude chat, Claude Code in the terminal, and API usage are unaffected.

Analysis note (not a quote): Trusted Devices' biometric step-up runs ON THE PHONE and authorizes
*viewing/steering the Remote Control session itself* — it is Anthropic's own device-trust layer
for the Claude account, entirely separate from and unaware of 1Password's SSH agent authorization
prompt, which is a macOS-local, 1Password-owned prompt tied to that specific Mac's Secure Enclave.
Satisfying one does not satisfy the other.

## Choose the right approach (comparison table, reproduced in full)

| | Trigger | Claude runs on | Setup | Best for |
|---|---|---|---|---|
| Dispatch | Message a task from the Claude mobile app | Your machine (Desktop) | Pair the mobile app with Desktop | Delegating work while you're away, minimal setup |
| Remote Control | Drive a running session from claude.ai/code or the Claude mobile app | Your machine (CLI or VS Code) | Run `claude remote-control` | Steering in-progress work from another device |
| Channels | Push events from a chat app like Telegram or Discord, or your own server | Your machine (CLI) | Install a channel plugin or build your own | Reacting to external events like CI failures or chat messages |
| Slack | Mention @Claude in a team channel | Anthropic cloud | Install the Slack app with Claude Code on the web enabled | PRs and reviews from team chat |
| Scheduled tasks | Set a schedule | CLI, Desktop, or cloud | Pick a frequency | Recurring automation like daily reviews |
