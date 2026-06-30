import csv
from collections import Counter, defaultdict

base = "/tmp/integration-audit-20260602T140159Z"

# Access-level ordering: lower index = higher in hierarchy.
SEAT_ORDER = [
    "SuperAdmin", "Admin", "President", "VicePresident", "Director",
    "Superintendent", "GeneralManager", "Manager", "Coordinator",
    "Supervisor", "SalesRepresentative",
]
rank = {name: index for index, name in enumerate(SEAT_ORDER)}


def load(name):
    with open(f"{base}/{name}") as handle:
        return list(csv.DictReader(handle))


normalized_users = load("phase1-normalized-user.csv")
app_users = load("phase1-app-user.csv")
app_seats = load("phase1-app-seat.csv")
mongo_users = load("phase1-mongo-user.csv")
identifiers = load("phase1-app-user-identifier.csv")

mongo_status_by_external = {row["external_id"]: row["integration_status"] for row in mongo_users}

# 4sk_<normalized_id> -> app user_id   (and reverse)
sk_to_app_user = {}
app_user_to_norm = {}
for row in identifiers:
    value = row["value"] or ""
    if value.startswith("4sk_"):
        norm_id = value[len("4sk_"):]
        sk_to_app_user[norm_id] = row["user_id"]
        app_user_to_norm[row["user_id"]] = norm_id

app_user_by_id = {row["user_id"]: row for row in app_users}

# app seat maps
seat_by_user = {}
seat_id_to_user = {}
for row in app_seats:
    user_id = row["user_id"]
    seat_by_user[user_id] = row
    seat_id_to_user[row["id"]] = user_id

normalized_ids = {row["id"] for row in normalized_users}

buckets = Counter()
cargo_crosstab = Counter()      # (truth_type, current_type) for mismatches
parent_buckets = Counter()
divergence_rows = []

for n in normalized_users:
    norm_id = n["id"]
    truth_type = n["type"]
    truth_parent = (n["parent_id"] or "").strip()
    app_user_id = sk_to_app_user.get(norm_id)

    if app_user_id is None:
        buckets["NOT_LINKED (no 4sk_ on app)"] += 1
        divergence_rows.append({
            "norm_id": norm_id, "app_user_id": "", "name": f'{n["first_name"]} {n["last_name"]}',
            "truth_type": truth_type, "current_type": "", "direction": "NOT_LINKED",
            "disabled": "", "mongo_status": mongo_status_by_external.get(norm_id, "?"),
            "truth_parent_norm_id": truth_parent, "current_parent_norm_id": "", "parent_match": "",
        })
        continue

    app = app_user_by_id.get(app_user_id)
    if app is None:
        buckets["LINKED but app user row missing"] += 1
        continue

    current_type = app["user_seat"]
    disabled = app["user_disabled"] == "true"

    # ---- parent picture (best effort) ----
    seat = seat_by_user.get(app_user_id)
    current_parent_norm_id = ""
    if seat and seat["parent_id"] and seat["parent_type"] == "Seat":
        current_parent_user_id = seat_id_to_user.get(seat["parent_id"])
        if current_parent_user_id:
            current_parent_norm_id = app_user_to_norm.get(current_parent_user_id, "OUTSIDE_INTEGRATOR")
    parent_match = (current_parent_norm_id == truth_parent) or (truth_parent == "" and current_parent_norm_id == "")

    # ---- cargo classification ----
    if current_type == truth_type:
        cargo_dir = "MATCH"
        if disabled:
            buckets["CARGO MATCH but app user DISABLED"] += 1
        else:
            buckets["CARGO MATCH"] += 1
    else:
        cargo_crosstab[(truth_type, current_type)] += 1
        if rank.get(truth_type, 99) < rank.get(current_type, 99):
            cargo_dir = "PROMOTION (truth higher)"
        else:
            cargo_dir = "DEMOTION (truth lower)"
        label = cargo_dir + (" [user DISABLED]" if disabled else "")
        buckets[label] += 1
        divergence_rows.append({
            "norm_id": norm_id, "app_user_id": app_user_id, "name": app["user_name"],
            "truth_type": truth_type, "current_type": current_type,
            "direction": cargo_dir, "disabled": disabled,
            "mongo_status": mongo_status_by_external.get(norm_id, "?"),
            "truth_parent_norm_id": truth_parent, "current_parent_norm_id": current_parent_norm_id,
            "parent_match": parent_match,
        })

    if not parent_match:
        parent_buckets["PARENT MISMATCH"] += 1
    else:
        parent_buckets["PARENT MATCH"] += 1

# orphan check: app 4sk_ ids not present in current normalized base
orphan_sk = [norm_id for norm_id in sk_to_app_user if norm_id not in normalized_ids]

print("================ CARGO RECONCILIATION (normalized.type = truth) ================")
total = len(normalized_users)
for label, count in sorted(buckets.items(), key=lambda kv: -kv[1]):
    print(f"  {label:45} {count:5}  ({100*count/total:.1f}%)")
print(f"  {'TOTAL normalized users':45} {total:5}")

print("\n================ CARGO MISMATCH CROSS-TAB (truth -> current) ================")
for (truth_type, current_type), count in sorted(cargo_crosstab.items(), key=lambda kv: -kv[1]):
    direction = "PROMOTION" if rank.get(truth_type, 99) < rank.get(current_type, 99) else "DEMOTION"
    print(f"  truth={truth_type:20} app={current_type:20} {direction:10} {count:5}")

print("\n================ PARENT PICTURE (best-effort, integrator scope) ================")
for label, count in parent_buckets.most_common():
    print(f"  {label:25} {count}")

print(f"\norphan 4sk_ identifiers on app not in current normalized base: {len(orphan_sk)}")
if orphan_sk[:10]:
    print("  examples:", orphan_sk[:10])

# write divergence detail CSV
out_csv = f"{base}/cargo-divergences.csv"
with open(out_csv, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=[
        "norm_id", "app_user_id", "name", "truth_type", "current_type",
        "direction", "disabled", "mongo_status",
        "truth_parent_norm_id", "current_parent_norm_id", "parent_match",
    ])
    writer.writeheader()
    writer.writerows(divergence_rows)
print(f"\nwrote {len(divergence_rows)} divergence rows -> {out_csv}")
