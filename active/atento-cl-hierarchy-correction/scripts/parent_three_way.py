import csv
from collections import Counter

base = "/tmp/integration-audit-20260602T140159Z"


def load(name):
    with open(f"{base}/{name}") as handle:
        return list(csv.DictReader(handle))


normalized = load("phase1-normalized-user.csv")
seats = load("phase1-app-seat.csv")
identifiers = load("phase1-app-user-identifier.csv")
events = load("phase1-normalized-hierarchy.csv")

sk_to_app = {}
app_to_norm = {}
for row in identifiers:
    value = row["value"] or ""
    if value.startswith("4sk_"):
        norm_id = value[4:]
        sk_to_app[norm_id] = row["user_id"]
        app_to_norm[row["user_id"]] = norm_id

seat_by_user = {row["user_id"]: row for row in seats}
seat_id_to_user = {row["id"]: row["user_id"] for row in seats}

# latest event parent per subject (by created_at), any event type carrying parent_id
latest_event_parent = {}
for event in sorted(events, key=lambda row: row["created_at"]):
    if event["parent_id"]:
        latest_event_parent[event["user_id"]] = event["parent_id"]

three_way = Counter()
app_follows_event = 0
app_follows_event_total = 0
real_pending = []  # app != latest event  => an event the integrator has not applied yet

for record in normalized:
    norm_id = record["id"]
    app_user_id = sk_to_app.get(norm_id)
    if app_user_id is None:
        continue

    users_parent = (record["parent_id"] or "").strip()          # U
    event_parent = latest_event_parent.get(norm_id, "")          # H (may be missing)

    seat = seat_by_user.get(app_user_id, {})
    app_parent_user = seat_id_to_user.get(seat.get("parent_id")) if seat.get("parent_id") else None
    app_parent = app_to_norm.get(app_parent_user, "OUTSIDE" if app_parent_user else "")  # A (norm id)

    # three-way label
    def same(left, right):
        return left == right and left != ""

    if same(app_parent, event_parent) and same(app_parent, users_parent):
        three_way["all three agree"] += 1
    elif same(app_parent, event_parent):
        three_way["app == event (users.parent_id is the outlier)"] += 1
    elif same(app_parent, users_parent):
        three_way["app == users.parent_id (event is the outlier)"] += 1
    elif same(event_parent, users_parent):
        three_way["event == users.parent_id, app differs (pending apply?)"] += 1
    elif app_parent == "" and users_parent == "" and event_parent == "":
        three_way["all root/empty"] += 1
    else:
        three_way["all three differ / other"] += 1

    # does the app reflect the latest event? (only when an event exists)
    if event_parent:
        app_follows_event_total += 1
        if app_parent == event_parent:
            app_follows_event += 1
        else:
            real_pending.append((norm_id, app_user_id, f"app={app_parent}", f"event={event_parent}", f"users={users_parent}"))

print("== THREE-WAY parent comparison (app seat vs hierarchy event vs users.parent_id) ==")
for label, count in three_way.most_common():
    print(f"  {count:5}  {label}")

print(f"\n== does the app reflect the LATEST hierarchy event? (subjects with an event) ==")
print(f"  app matches latest event: {app_follows_event} / {app_follows_event_total}")
print(f"  app does NOT match latest event (event pending/unapplied or app diverged): {len(real_pending)}")
print("  examples:")
for example in real_pending[:15]:
    print("   ", example)
