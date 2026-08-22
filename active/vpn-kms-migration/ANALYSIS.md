# ANALYSIS — VPN root-volume encryption and zone split, closing state

State of the Pritunl VPN infrastructure after the 2026-08-21 work, and the follow-ups that outlived it. Written so the loose ends survive the session that produced them.

## What the infrastructure looks like now

Both VPN hosts were replaced and both root volumes are encrypted with the VPN's own key (`alias/vpn`, `key/0f4e9ae3-59a1-4d66-a4ae-14936a615f1c`). The two hosts now sit in different availability zones, so a capacity shortage in one zone can no longer keep both down — which is the failure that started this work.

| | Instance | Zone | Root volume | Address |
|---|---|---|---|---|
| Production | `i-0109379cd1604ba87` | `sa-east-1c` | `vol-0c3b9d530991d0871`, encrypted | EIP `18.228.109.20` |
| Staging | `i-0d921702a2709325d` | `sa-east-1b` | `vol-01463d8480b4b3164`, encrypted | ephemeral, changes on every start |

Both ECS services run at `1/1`. Production serves the team; staging was reconfigured from scratch and validated end to end, including reaching a client network through the peering.

The management network's public subnets now cover three distinct zones — `a1`, `b1`, `c1` — after the subnet that duplicated zone `c` was removed and its address range reused for the new one in zone `b`.

**The host identity now survives instance replacement.** This was the risk that blocked the production apply for two days: Pritunl keeps its host identity in a file on the root volume, so replacing the instance used to register a second host and strand the VPN server on the dead one. The image sets the identity from the task definition instead, and the production replacement proved it against a genuinely empty volume — the host kept `f3ff579121944b7ba378cce9b7a8972b` and the server stayed attached to it.

## Follow-ups

### `vpn/import.tf` is applied and should be removed

The file adopted the two `random_id` resources that carry the Pritunl host identities. It has served its purpose, and the repository has done this before — commit `b495f0f` removed the previous batch of applied import blocks. While it stays, future plans on the `vpn` stack report the resources as already present in state.

### Two orphan Pritunl host records

Each instance replacement leaves one behind: `nickel-2046` in the production database, `xenon-4883` in staging, plus `cobalt-6899` in staging from the July MongoDB host swap. All three are attached to nothing — the servers list only the live host — so they are clutter rather than a fault.

The pattern is worth knowing rather than the individual records: the identity fix preserves the correct host, but it does not prevent the transient registration the container makes in its first moments, before the identity is set. Expect one new orphan per replacement until that is addressed upstream or in the entrypoint.

### The staging client profile must be re-downloaded after every replacement

Staging carries no Elastic IP by design — `modules/vpn/staging.tf` documents the reasoning, since an EIP would be billed permanently for a host that runs a few minutes a month. The address therefore changes on every start, and the Pritunl client profile embeds it. Editing the address by hand is not enough to be safe: the profile also carries a sync-hosts block used for automatic updates, and a stale one fails silently while the tunnel still works.

## Backup

`~/Downloads/vpn_mongo_dump_20260821_pos_migracao.json` — a logical dump of both `pritunl` and `pritunl-staging`, taken after the staging reconfiguration. 7,128,372 bytes, verified to parse, with collection counts matching the live databases. It restores Pritunl's content — organizations, users, servers, routes, hosts — but it is not a volume snapshot and does not rebuild the MongoDB host.

## What was not done

The EBS snapshot of the MongoDB host was never taken. It needs `ec2:CreateSnapshot`, which the identity stack grants only behind an MFA condition, and the elevation was unavailable at the moment it was attempted. The logical dump above covers the data that matters for Pritunl; the snapshot would additionally cover the machine.

## See also

- `../auth-001-dedicated-network/PLAN.md` — moving the Keycloak authenticator out of the shared management network, including the security-group finding that the Keycloak database and tasks accept the whole VPC range.
