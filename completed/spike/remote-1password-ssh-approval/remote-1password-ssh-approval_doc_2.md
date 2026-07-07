# Auxiliary source — 1Password Community threads and third-party workaround tool

## Source: "Forwarding biometric auth?" — 1Password Community
- URL: https://www.1password.community/discussions/developers/forwarding-biometric-auth/151389
- Fetched: 2026-07-06 (fetched twice; question and staff answer confirmed identical both times)

Question, asked by community member MattWallace:

> Is there any way to make `op signin` trigger biometric authentication back to the machine I'm initiating the SSH from?

Official reply, attributed to a 1Password staff member identified as "Phil":

> Biometric auth is limited to the local host, but you can use Service Accounts (available via Family/Business Accounts) to provide access to a specific Vault and Item.

Context: the question is about `op signin` / 1Password CLI unlock triggered from a remote SSH
session back to the biometric sensor on the machine the SSH connection originated from — i.e.,
the reverse direction of forwarding, and the same class of problem as "can Touch ID approval be
satisfied from somewhere other than the physical machine showing the prompt." It is not a
question about the SSH *agent's* per-key authorization prompt specifically, but both prompts are
produced by the same local 1Password desktop process and the same OS-level biometric hook
(Touch ID / Secure Enclave on macOS), so the staff answer is treated in the SPIKE as applicable
to both prompt types, with this scoping note preserved for the engineer's judgment.

## Source: "Any way to access to 1P SSH Agent on a Headless remote, if local agent can't be forwarded?" — 1Password Community
- URL: https://1password.community/discussion/140898/any-way-to-access-to-1p-ssh-agent-on-a-headless-remote-if-local-agent-cant-be-forwarded
- Fetch status: UNVERIFIED — direct fetch returned HTTP 404 Not Found. Content below is drawn
  only from WebSearch result snippets, not a confirmed page fetch, and is NOT used to sustain
  any Finding in SPIKE.md. Included here for the engineer's own follow-up only.

Search-snippet paraphrase (not a verified verbatim quote): on desktop, users with the 1Password
app and SSH agent enabled get approval prompts when using SSH, but this becomes problematic in
headless environments; the biometric prompt is immediately dismissed and authentication fails
when the local machine is locked or the display is asleep.

## Source: op-forward (third-party, community-built tool — not a 1Password product)
- URL: https://github.com/ekovshilovsky/op-forward
- Fetched: 2026-07-06

> The 1Password CLI requires desktop integration for biometric unlock (Touch ID on macOS). Inside headless VMs, containers, or remote SSH sessions, `op` commands fail because the biometric chain is broken.

Architecture, as stated by the tool's author:

> op shim → HTTP → SSH RemoteForward → Host daemon → op CLI → Touch ID

> Every privileged 1Password operation triggers biometric approval on the host. The proxy cannot bypass this.

Security caveats stated by the author:

> A compromised VM with access to the token file can execute any non-blocked `op` command, subject to Touch ID approval.

> If Touch ID is configured to not require approval for every `op` invocation (unusual but possible), the proxy would execute commands without biometric gates.

Note: op-forward is an unofficial, third-party tool, not a 1Password product. It solves the
opposite direction of the engineer's problem (a headless remote borrowing a present, physically
accessible host's Touch ID), not the case where nobody is physically present at the host at all.
It is included because it demonstrates that even a purpose-built forwarding tool cannot remove
the local biometric requirement — it only relays the request to the same local sensor.
