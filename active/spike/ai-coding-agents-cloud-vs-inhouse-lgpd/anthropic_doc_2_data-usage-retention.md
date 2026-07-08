# Auxiliary source — Anthropic data usage, retention, and Zero Data Retention (ZDR) for Claude Code

Combines three fetched primary docs. All URLs fetched 2026-07-07.

---

## Source A: https://code.claude.com/docs/en/data-usage

### Data training policy

> **Consumer users (Free, Pro, and Max plans)**: We give you the choice to allow your data to be used to improve future Claude models. We will train new models using data from Free, Pro, and Max accounts when this setting is on (including when you use Claude Code from these accounts).

> **Commercial users**: (Team and Enterprise plans, API, 3rd-party platforms, and Claude Gov) maintain existing policies: Anthropic does not train generative models using code or prompts sent to Claude Code under commercial terms, unless the customer has chosen to provide their data to us for model improvement (for example, the Development Partner Program).

### Data retention

> **Consumer users (Free, Pro, and Max plans)**:
> * Users who allow data use for model improvement: 5-year retention period to support model development and safety improvements
> * Users who don't allow data use for model improvement: 30-day retention period

> **Commercial users (Team, Enterprise, and API)**:
> * Standard: 30-day retention period
> * Zero data retention: available to qualified accounts for Claude Code on Claude for Enterprise. ZDR is not included in the standard Enterprise plan; it is enabled on a per-organization basis by your account team after confirming eligibility
> * Local caching: Claude Code clients store session transcripts locally in plaintext under `~/.claude/projects/` for 30 days by default to enable session resumption. Adjust the period with `cleanupPeriodDays`.

### Data access — local vs cloud

> [Remote Control](/en/remote-control) sessions follow the local data flow since all execution happens on your machine.

> Claude Code runs locally. To interact with the LLM, Claude Code sends data over the network. This data includes all user prompts and model outputs, encrypted in transit via TLS 1.2+.

Encryption at rest table:
| Provider | Encryption at rest |
|---|---|
| Anthropic API | Infrastructure-level disk encryption (AES-256). Enable Zero Data Retention (ZDR) for no server-side persistence. |
| Amazon Bedrock | AES-256 with AWS-managed keys. Customer-managed keys available via AWS KMS. |
| Google Cloud's Agent Platform | Google-managed encryption keys. CMEK available. |
| Microsoft Foundry | Requests route to Anthropic infrastructure with AES-256 disk encryption. |

### Cloud execution: Data flow and dependencies

> When using Claude Code on the web, sessions run in Anthropic-managed virtual machines instead of locally. In cloud environments:
> * **Code and data storage:** Your repository is cloned to an isolated VM. Code and session data are subject to the retention and usage policies for your account type (see Data retention section above)
> * **Credentials:** GitHub authentication is handled through a secure proxy; your GitHub credentials never enter the sandbox
> * **Network traffic:** All outbound traffic goes through a security proxy for audit logging and abuse prevention
> * **Session data:** Prompts, code changes, and outputs follow the same data policies as local Claude Code usage

**Significance**: this is the single most important sentence for the engineer's question — cloud-sandbox session data ("code changes", i.e. the generated files) is explicitly stated to follow the *same numeric retention policy* as local usage (30-day standard, or ZDR if enabled) — EXCEPT ZDR is explicitly disabled for this product surface (see Source C below). So cloud-sandbox sessions default to 30-day server-side retention of code/data with no ZDR path available.

---

## Source B: https://platform.claude.com/docs/en/manage-claude/api-and-data-retention

> **Zero data retention (ZDR):** Customer data is not stored at rest after the API response is returned, except where needed to comply with law or combat misuse.

> Where an API or feature doesn't require storage of customer prompts or responses, it may be eligible for ZDR. Where an API or feature necessarily requires storage of customer prompts or responses, Anthropic designs for the smallest possible retention footprint.

ZDR scope table (relevant rows):
- **Claude Code**: ZDR applies when used with Commercial organization API keys or through Claude Enterprise
- **Claude Managed Agents**: NOT ZDR-eligible — "Sessions are stateful resources; transcripts persist until you delete them."

> **What ZDR does NOT cover** ... **Claude Teams and Claude Enterprise:** Claude Teams and Claude Enterprise product interfaces are **not ZDR-eligible**, except for Claude Code when used through Claude Enterprise with ZDR enabled for the organization.

> Even with ZDR or HIPAA arrangements in place, Anthropic may retain data where required by law or to combat Usage Policy violations and malicious uses of Anthropic's platform. As a result, if a chat or session is flagged for such a violation, Anthropic may retain inputs and outputs for up to 2 years.

> **Is Claude Code eligible for ZDR?** Claude Code is eligible for ZDR through two paths: **API keys:** Claude Code used with pay-as-you-go API keys from a Commercial organization. **Claude Enterprise:** Claude Code used through Claude Enterprise with ZDR enabled for the organization. ZDR is enabled on a per-organization basis. Each new organization requires ZDR to be enabled separately by your account team.

---

## Source C: https://code.claude.com/docs/en/zero-data-retention

> Zero Data Retention (ZDR) for Claude Code is available to qualified accounts on Claude for Enterprise. When ZDR is enabled, prompts and model responses generated during Claude Code sessions are processed in real time and not stored by Anthropic after the response is returned, except where needed to comply with law or combat misuse.

> ZDR is not included in the standard Claude for Enterprise plan and cannot be enabled from your admin settings. It is available to qualified accounts and requires separate enablement by Anthropic.

> ### What ZDR covers
> ZDR covers model inference calls made through Claude Code on Claude for Enterprise. When you use Claude Code in your terminal, the prompts you send and the responses Claude generates are not retained by Anthropic.

**This sentence explicitly frames ZDR coverage as terminal/inference-call scoped ("When you use Claude Code in your terminal...") — not the web/cloud product.**

> ### Features disabled under ZDR
>
> | Feature | Reason |
> |---|---|
> | Claude Code on the Web | Requires server-side storage of conversation history. |
> | Cloud sessions from the Desktop app | Requires persistent session data that includes prompts and completions. |
> | Artifacts | Requires storing published page content on Anthropic-operated infrastructure. |
> | Feedback submission (`/feedback`) | Submitting feedback sends conversation data to Anthropic. |
>
> These features are blocked in the backend regardless of client-side display.

**This is the single clearest documented fact answering the engineer's core question**: Zero Data Retention and the Claude Code cloud/web sandbox are **mutually exclusive by design**. An organization cannot have both ZDR and cloud-sandbox sessions — enabling ZDR disables Claude Code on the Web entirely, and using Claude Code on the Web takes the account outside ZDR's scope for that data (standard 30-day retention applies instead, per Source A/B above).

> Even with ZDR enabled, Anthropic may retain data where required by law or to address Usage Policy violations. If a session is flagged for a policy violation, Anthropic may retain the associated inputs and outputs for up to 2 years, consistent with Anthropic's standard ZDR policy.
