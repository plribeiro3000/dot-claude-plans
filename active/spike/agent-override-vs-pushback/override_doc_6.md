# Auxiliary Source 6 — Aviation CRM and Authority Gradients

## Source A: FAA Advisory Circular AC 61-115 — Positive Exchange of Flight Controls
URL: https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentNumber/61-115
Fetched: 2026-06-23 (referenced via chsflightschool.com and skybrary content; AC text reconstructed from secondary sources; primary PDF not parsed)

### The Three-Step Ritual (verbatim procedure from secondary source chsflightschool.com)

Positive exchange of flight controls follows a mandatory three-step verbal ritual:

Step 1 — Transfer initiation: "You have the controls."
Step 2 — Confirmation: "I have the controls."
Step 3 — Final acknowledgment: "You have the controls."

"The first pilot initiates the transfer by saying 'You have the controls.' The receiving pilot responds 'I have the controls.' The first pilot then confirms the transfer with a final 'You have the controls.'"

### Why the three-step ritual exists

"Ambiguous control transfers have caused fatal accidents. In several documented cases, both pilots believed the other was flying the aircraft — each waiting for the other to respond to an emergency."

The three-step verbal ritual eliminates ambiguity: control transfer is ONLY complete when both parties have spoken and the final acknowledgment is given. There is no implicit transfer.

### The dual-confirmation requirement

"Until a positive verbal exchange has occurred and both pilots are aware of who is controlling the aircraft, neither pilot should relinquish control. A nod, a hand gesture, or an assumption is not a positive exchange."

The ritual requires BOTH parties to speak. Neither party can complete the transfer alone. The initiating pilot cannot simply hand off; the receiving pilot cannot simply take over.

---

## Source B: Crew Resource Management (CRM) — Authority Gradient
URL: https://en.wikipedia.org/wiki/Crew_resource_management
Fetched: 2026-06-23

### Definition of authority gradient

"An authority gradient describes the relative distribution of decision-making power between crew members. A steep gradient (where one person has much more authority than others) can inhibit subordinates from questioning or correcting errors by the authority figure."

### The steep gradient failure mode

"When the authority gradient is too steep, subordinates may notice a problem but fail to voice it, or voice it so tentatively that the authority figure does not recognize it as a challenge."

Documented in crash reports: "First Officer behavior patterns included 'hinting' rather than direct statements, deference even when the First Officer knew the approach was wrong, and failure to escalate after initial hint was ignored."

### CRM training: speaking up is an obligation

Modern CRM training explicitly counters the authority gradient: "CRM training teaches crew members that pointing out a potential error is NOT insubordination — it is a professional obligation. The captain's authority to make final decisions is not diminished by crew input; it requires it."

"Challenge and response checklists function as a structured mechanism for this: the challenge must be spoken, the response must be spoken, both are documented in the checklist."

### The PACE model (from UK aviation CRM)

"Probe, Alert, Challenge, Emergency" — an escalation protocol for situations where crew disagrees with captain's decision:

1. **Probe**: ask a neutral question to surface the concern ("Are we sure about the fuel calculation?")
2. **Alert**: state the concern directly ("I'm not comfortable with the fuel state")
3. **Challenge**: direct challenge ("We need to divert. I am not comfortable continuing.")
4. **Emergency**: invoke a formal emergency authority (rare — used when challenge is ignored in a safety-critical situation)

The PACE model is relevant because it provides a GRADUATED escalation: the agent can probe, alert, then challenge, with "E" being the emergency-override equivalent.

---

## Source C: United Airlines Flight 173 (1978) — The Steep Gradient Incident
URL: https://en.wikipedia.org/wiki/United_Airlines_Flight_173
Fetched: 2026-06-23

### What happened

"The captain became so focused on investigating a landing gear malfunction that he failed to notice the fuel state reaching critical levels. The first officer and flight engineer both noticed the fuel state but failed to communicate the urgency forcefully enough."

"The first officer made statements like 'We're going to lose an engine' but did not force a diversion. The captain did not register these as emergency warnings."

"The accident report attributed the crash in part to 'the failure of the other two flight crew members to effectively communicate the criticality of the fuel state to the captain.'"

### Why the incident matters for override design

Flight 173 is the canonical example of what happens when:
- Pushback is too gentle to register as a genuine objection
- The authority figure has no structured signal that "this is a real stop-everything concern, not a minor note"
- The subordinate does not escalate from "hint" to "challenge" to "emergency"

The design implication: an override protocol works in both directions. The human engineer needs an explicit signal to force agent compliance; but the agent also needs an escalation protocol that makes its genuine safety objections distinguishable from routine commentary. Neither a sycophantic agent (no resistance) nor an obstinate agent (ignores override) solves the problem.

---

## Source D: NASA — Lessons from Aviation CRM Applied to Operations
URL: https://ntrs.nasa.gov/citations/20040031083
Fetched: 2026-06-23 (search result excerpt)

### Key transfer: voice concern BEFORE the decision point

"CRM training emphasizes that crew input must happen before the decision is made, not after. A first officer who objects after the captain has committed to a course of action has a much smaller chance of changing the outcome."

The research finding: "the effectiveness of crew input drops sharply once a decision has been made and execution has begun."

Implication for the agent override: the agent's objection is most effective (and most expected) BEFORE the engineer has given the explicit override signal. Once the signal is given, both parties have committed. The override signal is the analog of "the captain has made the final call" — at that point, the debate is explicitly over.
