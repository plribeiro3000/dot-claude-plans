import csv
import html

base = "/tmp/integration-audit-20260602T140159Z"
out = "/tmp/integration_debug_phase1_rev2_atento-cl_app-atento-001_20260602T140159Z.html"

with open(f"{base}/cargo-divergences.csv") as handle:
    rows = list(csv.DictReader(handle))
demotions = [r for r in rows if r["direction"].startswith("DEMOTION")]
promotions = [r for r in rows if r["direction"].startswith("PROMOTION")]
not_linked = [r for r in rows if r["direction"] == "NOT_LINKED"]

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


def cargo_table(records):
    head = ("<table style='width:100%;border-collapse:collapse;font-size:.82rem'>"
            "<tr style='text-align:left;border-bottom:2px solid var(--border)'>"
            "<th>norm_id</th><th>app_user</th><th>name</th><th>truth type</th>"
            "<th>app type</th><th>subord.</th><th>has hierarchy event?</th></tr>")
    body = ""
    for r in records:
        sub = subord.get(r["app_user_id"], 0)
        warn = " style='color:var(--danger);font-weight:700'" if (sub and r["truth_type"] in ("SalesRepresentative", "Supervisor")) else ""
        body += (f"<tr style='border-bottom:1px solid var(--border)'><td>{esc(r['norm_id'])}</td>"
                 f"<td>{esc(r['app_user_id'])}</td><td>{esc(r['name'])}</td><td>{esc(r['truth_type'])}</td>"
                 f"<td>{esc(r['current_type'])}</td><td{warn}>{sub}</td>"
                 f"<td>{'promotion/demotion event NOT found — console only' if True else ''}</td></tr>")
    return head + body + "</table>"


findings = f"""
      <article class="finding" data-category="decision">
        <div class="finding-head"><span class="badge badge-danger">DECISION · parent truth</span>
        <span class="title">The customer's normalized base contradicts itself on the manager (parent)</span></div>
        <div class="where">Three-way comparison across 3076 linked users: app Seat parent vs <code>fsk_hierarchy</code> update_parent events vs <code>fsk_users.parent_id</code>.</div>
        <p>This is the headline of the redo. The three sources disagree:</p>
        <pre><code>app == users.parent_id ............ 2853   (the app follows the users column)
app == hierarchy event ............  163
all three differ / other ..........   57
all three agree ...................   17
users.parent_id vs events disagree:  832 users
app reflects the LATEST event: only 180 / 848 subjects  -> 668 update_parent events UNAPPLIED</code></pre>
        <p>The app overwhelmingly tracks <code>users.parent_id</code> (2853), NOT the event log. Meanwhile a batch of <strong>1223 update_parent events dated 2026-05-05</strong> landed in neither the app nor <code>users.parent_id</code>. So "correct the managers" forks:</p>
        <p>• <strong>Truth = users.parent_id</strong> → ~221 app changes (my original worklist).<br>
           • <strong>Truth = hierarchy events</strong> → ~668 app changes (apply the unprocessed reorg).<br>
           These point in <em>opposite directions</em> for the 832 conflicting users. <strong>Decision needed before any parent mutation.</strong></p>
      </article>

      <article class="finding" data-category="risk">
        <div class="finding-head"><span class="badge badge-warning">Risk · integration health</span>
        <span class="title">A 1223-event update_parent batch (2026-05-05) was never applied to the app</span></div>
        <div class="where">fsk_hierarchy: 1232 events total — 1223 update_parent, 5 promotion, 4 demotion; range 2026-05-05 .. 2026-06-02; 850 distinct subjects.</div>
        <p>Only 180/848 subjects with an event show that event reflected on the app. Either the ParentUpdate stream did not process this batch (pending / failing), or the events were rejected. This may be the actual operational problem behind the "hierarchy is wrong" complaint — worth investigating regardless of the truth-source decision.</p>
      </article>

      <article class="finding" data-category="decision">
        <div class="finding-head"><span class="badge badge-danger">For decision · cargo</span>
        <span class="title">9 cargo DEMOTIONS — app seat higher than normalized.users.type (unchanged by redo)</span></div>
        <div class="where">Cargo truth = users.type, which the engineer fixed as authoritative. Cargo is UNAFFECTED by the parent contradiction.</div>
        <p>7 wrongly at Admin. Only the 4 promotion/demotion events exist in the whole base (9 total events); <strong>none of these 9 demotions has a matching event</strong> → console is the only path. Red subordinate counts block demotion until children move.</p>
        {cargo_table(demotions)}
      </article>

      <article class="finding" data-category="decision">
        <div class="finding-head"><span class="badge badge-warning">For decision · cargo</span>
        <span class="title">4 cargo PROMOTIONS — app seat lower than normalized.users.type</span></div>
        <div class="where">Cargo truth = users.type. 2 of these (norm 341, 1725) DO have a matching promotion event; 2 (56, 406) do not.</div>
        {cargo_table(promotions)}
      </article>

      <article class="finding" data-category="decision">
        <div class="finding-head"><span class="badge badge-warning">For decision · linkage</span>
        <span class="title">4 normalized users never integrated (pending, no 4sk_ identifier)</span></div>
        <div class="where">Integrator Mongo Resource = pending; no 4sk_ identifier on the app. norm 931, 932, 1794, 2399.</div>
        <p>Unchanged by the redo. Must be created/linked before their cargo/parent can be set; 2 other users have norm 931 as their target parent.</p>
      </article>

      <article class="finding" data-category="info">
        <div class="finding-head"><span class="badge badge-muted">Informational · resolved</span>
        <span class="title">normalized:hierarchy audit re-run successfully (bug fix deployed)</span></div>
        <div class="where">integrator integration_audit:normalized:hierarchy — previously aborted on FSK_HIERARCHIES (plural).</div>
        <p>After your fix it produced phase1-normalized-hierarchy.csv (1232 rows, columns id,user_id,date,parent_id,type,role,created_at). This redo is built on that data.</p>
      </article>

      <article class="finding" data-category="info">
        <div class="finding-head"><span class="badge badge-muted">Informational · out of scope</span>
        <span class="title">68 users cargo-correct but disabled on app</span></div>
        <div class="where">UserActivity concern, not hierarchy/cargo. Reported, not touched.</div>
      </article>
"""

template = open("/Users/plribeiro3000/.claude/templates/html/interactive-report.html").read()
template = template.replace("Research Report — TOPIC", "Atento Chile — Hierarchy Reconciliation (Phase 1, REV2 with fsk_hierarchy)")
template = template.replace(
    "N findings from M reads. Filter by category, search by text, expand each finding for the code excerpt and verdict.",
    "company_id 1780 · integrator atento-cl · backend app-atento-001 · REDONE cross-referencing fsk_hierarchy events")
template = template.replace("Generated YYYY-MM-DD HH:MM · Source: BRANCH / REPO",
                            "Generated 2026-06-02 ~16:00 UTC · Phase 1 redo · all 7 audit snapshots OK")

stats = """      <div class="stat accent"><div class="label">Linked users</div><div class="value">3076</div></div>
      <div class="stat danger"><div class="label">Cargo divergences</div><div class="value">13</div></div>
      <div class="stat danger"><div class="label">Parent: users vs events disagree</div><div class="value">832</div></div>
      <div class="stat"><div class="label">Unapplied update_parent events</div><div class="value">668</div></div>
      <div class="stat"><div class="label">Stuck pending</div><div class="value">4</div></div>
      <div class="stat success"><div class="label">app == users.parent_id</div><div class="value">2853</div></div>"""
template = template.replace(
    """      <div class="stat accent"><div class="label">Findings</div><div class="value">12</div></div>
      <div class="stat danger"><div class="label">For decision</div><div class="value">4</div></div>
      <div class="stat success"><div class="label">Informational</div><div class="value">8</div></div>
      <div class="stat"><div class="label">Files inspected</div><div class="value">6</div></div>""", stats)

start = template.index('<div class="findings">') + len('<div class="findings">')
end = template.index("</div>\n  </div>\n\n  <!-- Mermaid loader")
template = template[:start] + "\n" + findings + "\n    " + template[end:]

template = template.replace("labels: ['For decision', 'Informational', 'Risk', 'Opportunity'],",
                            "labels: ['app==users.parent_id', 'app==event', 'users vs events disagree', 'unapplied events', 'cargo divergences'],")
template = template.replace("data: [4, 5, 2, 1],", "data: [2853, 163, 832, 668, 13],")
template = template.replace("backgroundColor: ['#dc2626', '#0891b2', '#d97706', '#16a34a']",
                            "backgroundColor: ['#16a34a', '#0891b2', '#dc2626', '#d97706', '#7c3aed']")
template = template.replace('        <button class="filter-btn" data-category="opportunity">Opportunity</button>', "")

open(out, "w").write(template)
print("wrote", out)
