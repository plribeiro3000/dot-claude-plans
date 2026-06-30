import csv
from collections import Counter

base = "/tmp/integration-audit-20260602T140159Z"


def load(name):
    with open(f"{base}/{name}") as handle:
        return list(csv.DictReader(handle))


events = load("phase1-normalized-hierarchy.csv")
normalized = load("phase1-normalized-user.csv")
worklist = load("correction-worklist.csv")

normalized_by_id = {row["id"]: row for row in normalized}

print("== hierarchy event TYPE distribution ==")
for value, count in Counter(event["type"] for event in events).most_common():
    print(f"  {value!r:18} {count}")

dates = sorted(event["date"] for event in events if event["date"])
print(f"\nevents: {len(events)}  date range: {dates[0]} .. {dates[-1]}")
print("distinct subject users in events:", len({event['user_id'] for event in events}))

# latest event per subject user, by created_at
latest_cargo_role = {}
latest_parent_id = {}
for event in sorted(events, key=lambda row: row["created_at"]):
    subject_id = event["user_id"]
    if event["type"] in ("promotion", "demotion") and event["role"]:
        latest_cargo_role[subject_id] = event["role"]
    if event["parent_id"]:
        latest_parent_id[subject_id] = event["parent_id"]

cargo_agree = cargo_disagree = 0
for subject_id, role in latest_cargo_role.items():
    record = normalized_by_id.get(subject_id)
    if not record:
        continue
    if record["type"] == role:
        cargo_agree += 1
    else:
        cargo_disagree += 1

parent_agree = parent_disagree = 0
for subject_id, parent_norm_id in latest_parent_id.items():
    record = normalized_by_id.get(subject_id)
    if not record:
        continue
    if (record["parent_id"] or "") == (parent_norm_id or ""):
        parent_agree += 1
    else:
        parent_disagree += 1

print("\n== consistency: latest event vs users column ==")
print(f"  cargo  (event role vs users.type):        agree={cargo_agree} disagree={cargo_disagree}")
print(f"  parent (event parent vs users.parent_id): agree={parent_agree} disagree={parent_disagree}")

has_event = Counter()
annotated = []
for work in worklist:
    norm_id = work["norm_id"]
    operation = work["operation"]
    matched = "no event"
    if operation in ("promotion", "demotion"):
        if latest_cargo_role.get(norm_id) == work["target_type"]:
            matched = "event matches target role"
        elif norm_id in latest_cargo_role:
            matched = f"event exists but role={latest_cargo_role[norm_id]} != target"
    elif operation == "parent_update":
        if latest_parent_id.get(norm_id) == work["target_parent_norm"]:
            matched = "event matches target parent"
        elif norm_id in latest_parent_id:
            matched = f"event exists but parent={latest_parent_id[norm_id]} != target"
    elif operation == "LINK_THEN_CREATE":
        matched = "n/a (never integrated)"
    has_event[f"{operation}: {matched}"] += 1
    annotated_row = dict(work)
    annotated_row["hierarchy_event"] = matched
    annotated.append(annotated_row)

print("\n== worklist nodes vs hierarchy events (does a corrective event already exist?) ==")
for key, count in sorted(has_event.items()):
    print(f"  {count:4}  {key}")

out = f"{base}/correction-worklist-with-events.csv"
with open(out, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(annotated[0].keys()))
    writer.writeheader()
    writer.writerows(annotated)
print(f"\nwrote annotated worklist -> {out}")
