import csv
from collections import Counter, defaultdict

base = "/tmp/integration-audit-20260602T140159Z"

SEAT_ORDER = [
    "SuperAdmin", "Admin", "President", "VicePresident", "Director",
    "Superintendent", "GeneralManager", "Manager", "Coordinator",
    "Supervisor", "SalesRepresentative",
]
rank = {name: index for index, name in enumerate(SEAT_ORDER)}


def load(name):
    with open(f"{base}/{name}") as handle:
        return list(csv.DictReader(handle))


normalized = load("phase1-normalized-user.csv")
seats = load("phase1-app-seat.csv")
identifiers = load("phase1-app-user-identifier.csv")
app_users = load("phase1-app-user.csv")

mongo = {r["external_id"]: r["integration_status"] for r in load("phase1-mongo-user.csv")}
app_user_by_id = {r["user_id"]: r for r in app_users}

sk_to_app = {}
app_to_norm = {}
for r in identifiers:
    value = r["value"] or ""
    if value.startswith("4sk_"):
        norm_id = value[4:]
        sk_to_app[norm_id] = r["user_id"]
        app_to_norm[r["user_id"]] = norm_id

seat_by_user = {r["user_id"]: r for r in seats}
seat_id_to_user = {r["id"]: r["user_id"] for r in seats}

# current subordinate counts per app user (children pointing at this user's seat)
children = defaultdict(list)
for r in seats:
    if r["parent_id"] and r["parent_type"] == "Seat":
        parent_user = seat_id_to_user.get(r["parent_id"])
        if parent_user:
            children[parent_user].append(r["user_id"])

worklist = []
for n in normalized:
    norm_id = n["id"]
    target_type = n["type"]
    target_parent_norm = (n["parent_id"] or "").strip()
    app_user_id = sk_to_app.get(norm_id)

    if app_user_id is None:
        worklist.append({
            "app_user_id": "", "norm_id": norm_id, "name": f'{n["first_name"]} {n["last_name"]}',
            "current_type": "", "target_type": target_type, "operation": "LINK_THEN_CREATE",
            "current_parent_app": "", "target_parent_app": sk_to_app.get(target_parent_norm, ""),
            "target_parent_norm": target_parent_norm, "blockers": f"mongo={mongo.get(norm_id,'?')}; no 4sk_ identifier on app",
        })
        continue

    seat = seat_by_user.get(app_user_id, {})
    current_type = seat.get("type", "")
    current_parent_user = seat_id_to_user.get(seat.get("parent_id")) if seat.get("parent_id") else None
    current_parent_norm = app_to_norm.get(current_parent_user) if current_parent_user else None
    target_parent_app = sk_to_app.get(target_parent_norm, "") if target_parent_norm else ""

    # operation classification
    if current_type == target_type:
        if target_parent_norm == "" and current_parent_user is None:
            continue  # full match, root
        if current_parent_norm == target_parent_norm:
            continue  # full match
        operation = "parent_update"
    elif rank.get(target_type, 99) < rank.get(current_type, 99):
        operation = "promotion"
    else:
        operation = "demotion"

    blockers = []
    # target parent resolvability
    if target_type != "Admin":
        if target_parent_norm == "":
            blockers.append("target=non-Admin but normalized parent_id empty")
        elif target_parent_app == "":
            blockers.append(f"target parent norm={target_parent_norm} not linked on app (pending?)")
    # demotion subordinate conflict
    if operation == "demotion":
        kids = children.get(app_user_id, [])
        if kids:
            kid_types = {seat_by_user.get(k, {}).get("type", "") for k in kids}
            highest_kid = min((rank.get(t, 99) for t in kid_types), default=99)
            if highest_kid <= rank.get(target_type, 99):
                blockers.append(f"{len(kids)} subordinate(s) at/above target ({sorted(kid_types)}) -> move children first")
    # current parent outside integrator
    if operation == "parent_update" and current_parent_user and current_parent_norm is None:
        blockers.append("current parent is OUTSIDE integrator (atento-own) -> confirm intended")
    if operation == "parent_update" and target_parent_norm != "" and current_parent_user is None:
        blockers.append("normalized has parent but app seat is ROOT -> confirm")

    worklist.append({
        "app_user_id": app_user_id, "norm_id": norm_id, "name": app_user_by_id.get(app_user_id, {}).get("user_name", ""),
        "current_type": current_type, "target_type": target_type, "operation": operation,
        "current_parent_app": current_parent_user or "", "target_parent_app": target_parent_app,
        "target_parent_norm": target_parent_norm, "blockers": " | ".join(blockers),
    })

# processing order: target topological by target level (parents before children),
# but demotions deferred until after promotions+parent_updates (children moved off first)
op_rank = {"promotion": 0, "parent_update": 1, "demotion": 2, "LINK_THEN_CREATE": 3}
worklist.sort(key=lambda w: (op_rank.get(w["operation"], 9), rank.get(w["target_type"], 99)))

out = f"{base}/correction-worklist.csv"
with open(out, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=[
        "app_user_id", "norm_id", "name", "current_type", "target_type", "operation",
        "current_parent_app", "target_parent_app", "target_parent_norm", "blockers",
    ])
    writer.writeheader()
    writer.writerows(worklist)

print("== OPERATION COUNTS ==")
for op, count in Counter(w["operation"] for w in worklist).most_common():
    print(f"  {op:16} {count}")
print(f"  {'TOTAL nodes':16} {len(worklist)}")

print("\n== nodes WITH blockers ==")
blocked = [w for w in worklist if w["blockers"]]
print(f"  {len(blocked)} nodes carry a blocker/flag")
bcat = Counter()
for w in blocked:
    for piece in w["blockers"].split(" | "):
        key = piece.split("(")[0].split("->")[0].strip()[:55]
        bcat[key] += 1
for key, count in bcat.most_common():
    print(f"   {count:4}  {key}")

print(f"\nwrote {len(worklist)} -> {out}")
