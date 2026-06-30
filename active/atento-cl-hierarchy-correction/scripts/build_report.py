import csv
import html

base = "/tmp/integration-audit-20260602T140159Z"
out = "/tmp/integration_debug_phase1_atento-cl_app-atento-001_20260602T140159Z.html"

with open(f"{base}/cargo-divergences.csv") as handle:
    rows = list(csv.DictReader(handle))

cargo = [r for r in rows if r["direction"] in ("PROMOTION (truth higher)", "DEMOTION (truth lower)")]
demotions = [r for r in cargo if r["direction"].startswith("DEMOTION")]
promotions = [r for r in cargo if r["direction"].startswith("PROMOTION")]
not_linked = [r for r in rows if r["direction"] == "NOT_LINKED"]

# subordinate counts were printed by refine.py; recompute here for the table
import collections
with open(f"{base}/phase1-app-seat.csv") as handle:
    seats = list(csv.DictReader(handle))
seat_id_to_user = {s["id"]: s["user_id"] for s in seats}
subord = collections.Counter()
for s in seats:
    if s["parent_id"] and s["parent_type"] == "Seat":
        pu = seat_id_to_user.get(s["parent_id"])
        if pu:
            subord[pu] += 1


def esc(value):
    return html.escape(str(value))


def table(records):
    head = ("<table style='width:100%;border-collapse:collapse;font-size:.82rem'>"
            "<tr style='text-align:left;border-bottom:2px solid var(--border)'>"
            "<th>norm_id</th><th>app_user_id</th><th>name</th><th>truth (normalized.type)</th>"
            "<th>current (app seat)</th><th>subordinates</th><th>parent_match</th></tr>")
    body = ""
    for r in records:
        sub = subord.get(r["app_user_id"], 0)
        warn = " style='color:var(--danger);font-weight:700'" if (sub and (r["truth_type"] in ("SalesRepresentative", "Supervisor"))) else ""
        body += (f"<tr style='border-bottom:1px solid var(--border)'>"
                 f"<td>{esc(r['norm_id'])}</td><td>{esc(r['app_user_id'])}</td><td>{esc(r['name'])}</td>"
                 f"<td>{esc(r['truth_type'])}</td><td>{esc(r['current_type'])}</td>"
                 f"<td{warn}>{sub}</td><td>{esc(r['parent_match'])}</td></tr>")
    return head + body + "</table>"


def nl_table(records):
    head = ("<table style='width:100%;border-collapse:collapse;font-size:.82rem'>"
            "<tr style='text-align:left;border-bottom:2px solid var(--border)'>"
            "<th>norm_id</th><th>name</th><th>truth (normalized.type)</th><th>mongo status</th></tr>")
    body = ""
    for r in records:
        body += (f"<tr style='border-bottom:1px solid var(--border)'>"
                 f"<td>{esc(r['norm_id'])}</td><td>{esc(r['name'])}</td>"
                 f"<td>{esc(r['truth_type'])}</td><td>{esc(r['mongo_status'])}</td></tr>")
    return head + body + "</table>"


findings = f"""
      <article class="finding" data-category="decision">
        <div class="finding-head"><span class="badge badge-danger">For decision · cargo</span>
        <span class="title">9 cargo DEMOTIONS — app seat is higher than normalized.type</span></div>
        <div class="where">Integrator users whose current 4Shark seat sits above the cargo declared in the normalized <code>users.type</code>. 7 of these are wrongly at <strong>Admin</strong> (explains app Admin count 15 vs normalized 3).</div>
        <p>Truth = <code>normalized.users.type</code>. These users must be demoted to match. <strong>Several are blocked</strong>: a user cannot be demoted to SalesRepresentative/Supervisor while it still has subordinates (demotion guardrail: new role must stay above the highest subordinate). Rows in red have subordinates that must be re-parented first.</p>
        {table(demotions)}
      </article>

      <article class="finding" data-category="decision">
        <div class="finding-head"><span class="badge badge-danger">For decision · cargo</span>
        <span class="title">4 cargo PROMOTIONS — app seat is lower than normalized.type</span></div>
        <div class="where">Integrator users whose current 4Shark seat sits below the cargo declared in the normalized <code>users.type</code>.</div>
        <p>Truth = <code>normalized.users.type</code>. Promotion requires the new manager to hold a role strictly higher than the new role; <code>parent_match=False</code> means the immediate manager also needs review/realignment as part of the promotion call.</p>
        {table(promotions)}
      </article>

      <article class="finding" data-category="risk">
        <div class="finding-head"><span class="badge badge-warning">Risk · ordering</span>
        <span class="title">Demotions to SalesRep/Supervisor blocked by existing subordinates</span></div>
        <div class="where">App-side Seat hierarchy. The demotion API rejects with <code>conflicted</code> when the target lower role would sit below the user's current reports.</div>
        <p>norm_id 3030 (8 reports), 3048 (7), 3023 (5), 3056 (1) → target SalesRepresentative cannot have reports. norm_id 1809 → Coordinator (2 reports — must confirm reports are below Coordinator). The reports must be moved to their correct parents <strong>before</strong> these demotions can succeed. This makes the demotion bucket depend on the parent bucket.</p>
      </article>

      <article class="finding" data-category="decision">
        <div class="finding-head"><span class="badge badge-warning">For decision · linkage</span>
        <span class="title">4 normalized users never integrated (stuck pending, no 4sk_ identifier on app)</span></div>
        <div class="where">Integrator Mongo Resource = <code>pending</code>; no <code>4sk_&lt;id&gt;</code> UserIdentifier exists on the app. Cargo cannot be set on a user that does not exist/linked on the app.</div>
        <p>These are a different bucket from cargo: they were never created on the app. Correcting them means first creating/linking the user (or finding the existing app user and attaching the <code>4sk_</code> identifier + <code>integrate!</code>), then the cargo follows.</p>
        {nl_table(not_linked)}
      </article>

      <article class="finding" data-category="decision">
        <div class="finding-head"><span class="badge badge-info">For decision · scope</span>
        <span class="title">~221 immediate-manager (parent) divergences — outside "cargo", inside "hierarquia"</span></div>
        <div class="where">App Seat parent vs normalized <code>users.parent_id</code>, within integrator scope.</div>
        <p>Breakdown: <strong>188</strong> different integrator parent · <strong>26</strong> app parent is an Atento-own (non-integrator) user · <strong>7</strong> normalized has a parent but app seat is root. The objective said "baseado no <em>cargo</em>", so these are reported separately — the scope decision determines whether the correction plan includes them (ParentUpdate / seat re-parenting) or stops at the 13 cargo fixes.</p>
      </article>

      <article class="finding" data-category="info">
        <div class="finding-head"><span class="badge badge-muted">Informational · out of scope</span>
        <span class="title">68 users: cargo correct but DISABLED on app</span></div>
        <div class="where">Cargo matches normalized.type, but the app user is disabled. This is a UserActivity concern, not a cargo/hierarchy one.</div>
        <p>The normalized audit dump carries no active/inactive flag, so I cannot tell from this data whether they should be active. Flagged for awareness; out of scope for cargo correction.</p>
      </article>

      <article class="finding" data-category="risk">
        <div class="finding-head"><span class="badge badge-warning">Risk · root cause</span>
        <span class="title">The integrator will NOT self-heal cargo from a corrected users.type</span></div>
        <div class="where">Integrator pipeline. The 10 user-level streams set the seat only at user creation (filtered by <code>type</code>); ongoing cargo changes flow exclusively through the <code>hierarchy</code> events table (promotion/demotion), not from <code>users.type</code> changing.</div>
        <p>So editing <code>users.type</code> in the normalized base does not retroactively promote/demote an existing user. Correction must be applied either (a) 4Shark-side via the app console (SeatPromotionForm / SeatDemotionForm / ParentSeatForm), or (b) customer-side by pushing promotion/demotion rows into the <code>hierarchy</code> table and re-running integration. This is the core approach decision for the plan.</p>
      </article>

      <article class="finding" data-category="info">
        <div class="finding-head"><span class="badge badge-muted">Informational · tooling</span>
        <span class="title">Audit task bug: integration_audit:normalized:hierarchy queries the wrong table</span></div>
        <div class="where">integrator <code>lib/tasks/integration_audit/normalized/hierarchy.rake:28</code> on master.</div>
        <p>It calls <code>connection.page(:hierarchies, ...)</code> → resolves to <code>FSK_HIERARCHIES</code> (plural), but the normalized table is <code>FSK_HIERARCHY</code> (singular, per <code>NORMALIZED_SCHEMA table: 'hierarchy'</code>). Task aborts with <em>Invalid object name 'FSK_HIERARCHIES'</em>. Not blocking this audit (cargo truth comes from <code>users.type</code>), but the task is broken and should be fixed in a separate PR.</p>
        <pre><code>Sequel::DatabaseError: TinyTds::Error: Invalid object name 'FSK_HIERARCHIES'.
  integration_audit/normalized/hierarchy.rake:28  connection.page(:hierarchies, '', last_id)</code></pre>
      </article>
"""

template = open("/Users/plribeiro3000/.claude/templates/html/interactive-report.html").read()

template = template.replace("Research Report — TOPIC", "Atento Chile — Hierarchy/Cargo Reconciliation (Phase 1)")
template = template.replace(
    "N findings from M reads. Filter by category, search by text, expand each finding for the code excerpt and verdict.",
    "company_id 1780 · integrator atento-cl · backend app-atento-001 · normalized.users.type = source of truth")
template = template.replace("Generated YYYY-MM-DD HH:MM · Source: BRANCH / REPO",
                            "Generated 2026-06-02 14:0X UTC · Phase 1 (Discovery) · 6/7 audit snapshots OK")

stats = """      <div class="stat accent"><div class="label">Normalized users (truth)</div><div class="value">3081</div></div>
      <div class="stat danger"><div class="label">Cargo divergences</div><div class="value">13</div></div>
      <div class="stat danger"><div class="label">Stuck pending</div><div class="value">4</div></div>
      <div class="stat"><div class="label">Parent divergences</div><div class="value">~221</div></div>
      <div class="stat success"><div class="label">Cargo OK (active)</div><div class="value">2996</div></div>
      <div class="stat"><div class="label">Cargo OK but disabled</div><div class="value">68</div></div>"""
template = template.replace(
    """      <div class="stat accent"><div class="label">Findings</div><div class="value">12</div></div>
      <div class="stat danger"><div class="label">For decision</div><div class="value">4</div></div>
      <div class="stat success"><div class="label">Informational</div><div class="value">8</div></div>
      <div class="stat"><div class="label">Files inspected</div><div class="value">6</div></div>""", stats)

# replace the findings block
start = template.index('<div class="findings">') + len('<div class="findings">')
end = template.index("</div>\n  </div>\n\n  <!-- Mermaid loader")
template = template[:start] + "\n" + findings + "\n    " + template[end:]

# chart data
template = template.replace("labels: ['For decision', 'Informational', 'Risk', 'Opportunity'],",
                            "labels: ['Cargo demotion', 'Cargo promotion', 'Stuck pending', 'Parent divergence', 'Cargo-OK disabled'],")
template = template.replace("data: [4, 5, 2, 1],",
                            "data: [9, 4, 4, 221, 68],")
template = template.replace("backgroundColor: ['#dc2626', '#0891b2', '#d97706', '#16a34a']",
                            "backgroundColor: ['#dc2626', '#d97706', '#7c3aed', '#0891b2', '#78716c']")
# filter buttons
template = template.replace(
    """        <button class="filter-btn" data-category="opportunity">Opportunity</button>""",
    "")

open(out, "w").write(template)
print("wrote", out)
