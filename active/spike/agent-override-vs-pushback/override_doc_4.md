# Auxiliary Source 4 — Break-Glass Access Control & Two-Person Rule

## Source A: Break-Glass Pattern (Security/SRE literature)
URL: https://cloud.google.com/blog/products/identity-security/rethinking-break-glass-procedures-for-cloud-environments
Fetched: 2026-06-23

### Definition

"'Break glass' is a term borrowed from emergency response: in an emergency, you break the glass to pull the fire alarm or access the fire extinguisher. In IT security, break-glass access refers to an emergency procedure that allows an individual to gain access to resources they wouldn't normally be allowed to access, to respond to an emergency situation."

### Structural requirements for valid break-glass

Google's definition identifies four structural elements:
1. **Rarity / non-default**: break-glass is reserved for emergency situations; it is not a normal path
2. **Explicit invocation**: requires a deliberate action (not automatic), often with explicit acknowledgment of the emergency
3. **Logging / audit trail**: every break-glass invocation is recorded with who used it, when, and why
4. **Review and accountability**: break-glass usage is reviewed post-hoc; if the invocation was not justified by a genuine emergency, consequences follow

### Why logging matters for the override design

"Without logging, break-glass becomes a routine access path. Organizations that implement break-glass without mandatory post-hoc review find it becomes the default rather than the exception."

"The audit trail is not bureaucracy — it is what makes the mechanism legitimate. The knowledge that the use is recorded changes the psychology of the user. They are no longer making an anonymous judgment; they are making a documented one with their name on it."

---

## Source B: AWS documentation on break-glass accounts
URL: https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/emergency-access.html
Fetched: 2026-06-23 (via search result excerpt)

### AWS framing

"Emergency access accounts should be used only when all other access methods are unavailable. Use of these accounts should trigger immediate notification, be time-limited, and require post-use review."

### Key element: responsibility transfer is explicit

"When an operator invokes emergency access, they are accepting personal responsibility for the actions taken. The account audit trail makes this non-repudiable."

The AWS approach requires documenting the reason before granting access, not after — a "pre-mortem" that states the emergency and the planned action.

---

## Source C: The Two-Person Rule / Dual-Key Authorization
URL: https://en.wikipedia.org/wiki/Two-person_rule
Fetched: 2026-06-23

### Definition

"A two-person rule is a control mechanism designed to achieve a high level of security for especially critical material or operations. Under this rule, all access and actions requires the presence of two authorized people at all times."

### Origin: nuclear weapons safety

"The two-person rule was developed as a nuclear weapons safety protocol to prevent unauthorized launch. A single operator, regardless of rank or stated authorization, cannot complete a critical action alone. Both parties must independently authenticate before the action proceeds."

### What the two-person rule provides structurally

- **Prevention of impulsive action**: requiring a second party introduces a mandatory pause
- **Social accountability**: the action is now witnessed; the second party becomes a co-responsible party
- **Reduced error rate**: both parties must understand the action independently — this surfaces misunderstandings before execution
- **Not a veto**: the second party's role is to verify that the first party has authority and understands what they are doing — NOT to independently evaluate whether the action is wise

### Application to AI override design

The two-person rule analogy for an AI agent override: the "second person" might be the agent itself, acting as a witness by requiring an explicit acknowledgment sequence from the human. The agent does not veto — but it does require the human to state the override explicitly and consciously, making the authorization non-ambient.

---

## Source D: SRE Industry Context — "Toil" vs. "Friction"
URL: https://sre.google/sre-book/eliminating-toil/
Fetched: 2026-06-23 (via search result excerpt)

### Intentional vs. unintentional friction

SRE literature distinguishes:
- **Toil**: repetitive, low-value operational work that should be automated away
- **Intentional friction**: deliberate resistance designed to prevent impulsive action on high-risk operations

"Some friction is valuable. The friction of requiring a PR for production changes is not overhead — it is a forcing function for review. The goal of automation is not to remove all friction, but to remove unintentional friction while preserving friction that serves a safety function."

This maps directly to the override design: the override signal should have intentional friction — enough that it cannot be invoked accidentally or habitually, but not so much that it is unavailable in a genuine emergency.
