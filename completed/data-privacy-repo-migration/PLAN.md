# PLAN — Migrate the client-offboarding runtime tool to `4shark/data-privacy`

## Goal & context

Move the **privileged runtime tool** (`strip_attachments.py` — domain-wide-delegation Gmail
read/delete) out of the broadly-read `terraform` repo into a new, access-restricted repo
**`4shark/data-privacy`**, so fewer people can read/tamper with the code that wields the capability.
The **provisioning** of the capability (GCP project + service account + domain-wide delegation) stays
in `terraform/client-offboarding/` as IaC. The two cross-reference each other.

This is the second of the two security layers agreed with the engineer:
- **Key** (who can *obtain* the capability) — already solved: the SA key lives only in the
  engineer's own `Terraform ENV` 1Password item (no shared item); doc corrected in terraform #490.
- **Code** (who can *tamper* with the tool) — this migration.

Naming follows the community convention (name by discipline, not by role/law): `data-privacy`
(not `dpo`, not `lgpd`).

### Prerequisites (engineer-side, before this migration runs)
1. terraform **#491** merged + applied (identity stack, `AWS_PROFILE=ivo`) — creates the
   `data-privacy` GitHub team (secret, sole member `plribeiro3000`, `admin` on the repo).
2. The **`4shark/data-privacy` repo created** on GitHub (Terraform does not create repos here).
   The team→repo grant in #491 only applies once the repo exists.

## Scope — what moves vs what stays

| File (in `terraform/client-offboarding/`) | Action | Where it lands |
|---|---|---|
| `scripts/strip_attachments.py` | **move** | `data-privacy` repo → `client-offboarding/scripts/strip_attachments.py` |
| `.envrc` (reads SA key + `ANTHROPIC_API_KEY` for the script) | **move** | `data-privacy` repo → `client-offboarding/.envrc` |
| `README.md` (run/setup half) | **split** | run/setup half → new repo README; provisioning half stays |
| `main.tf`, `providers.tf`, `variables.tf` | **stay** | terraform (provisioning IaC) |
| `.terraform.lock.hcl`, `stack.tm.hcl` | **stay** | terraform |
| `offboarding-aster/` (untracked run output, client PII) | **delete, do not migrate** | — (runs write to `/tmp` per the rule) |

The trimmed `terraform/client-offboarding/README.md` keeps only "what Terraform manages /
how to provision" and **points to the `data-privacy` repo** for the runtime tool.

## Target structure of `4shark/data-privacy`

```
data-privacy/
├── README.md                     # what this repo is: privileged privacy-ops tooling (restricted)
├── CHANGELOG.md                  # Keep a Changelog / SemVer (new repo)
├── client-offboarding/
│   ├── README.md                 # run + setup (moved/adapted from the terraform stack README)
│   ├── .envrc                    # reads CLIENT_OFFBOARDING_SA_KEY + ANTHROPIC_API_KEY from your 1P
│   ├── requirements.txt          # google-auth, google-api-python-client, anthropic (pin the .venv)
│   └── scripts/
│       └── strip_attachments.py
├── .github/                      # CI + governance (see decision D2)
│   └── ...
├── CODEOWNERS                    # = the data-privacy team / you
└── .gitignore                    # ignore any local run output, .venv, key.json
```

## Open decisions (resolve at execution — do NOT assume)

- **D1 — Branch model.** Full org GitFlow/HubFlow (`master` + `develop`) like the other repos, or a
  lighter single-branch (`main` + PRs) for a tiny single-owner tool repo? (Recommendation: lighter
  `main` + PRs — this repo has no releases/tags and one maintainer; HubFlow adds ceremony with no
  payoff. Confirm with the engineer.)
- **D2 — Branch protection + "Verify Minimum Age" CI.** To add `data-privacy` to the identity
  `code_repositories` set (master/develop protection + required `Verify Minimum Age` check), the repo
  must carry the age-check workflow + script (else the required check never passes and PRs can't
  merge). Options: (a) full model — port `.github/workflows/verify-minimum-age.yaml` + script +
  Renovate; (b) lighter — basic PR-required protection on the default branch, no age check. Tie this
  to D1.
- **D3 — Git history.** Fresh copy of `strip_attachments.py` into the new repo (simple), or
  `git filter-repo` to preserve history (overkill for one file). Recommendation: fresh copy + a note
  in the new repo's CHANGELOG/README that it came from `terraform/client-offboarding/`.

## Execution phases (ordered — respect the dependencies)

1. **[blocked on prerequisites]** Confirm #491 applied + the `data-privacy` repo exists and the
   `data-privacy` team has `admin` on it.
2. **Scaffold the new repo** — README (what this repo is), CHANGELOG, `.gitignore` (ignore `.venv`,
   `key.json`, any local output), CODEOWNERS, and the branch model per D1.
3. **Move the tool** — copy `scripts/strip_attachments.py` + `.envrc` into `client-offboarding/`;
   add `requirements.txt` capturing the three deps; adapt the run/setup README. Verify it runs
   (`.venv/bin/python scripts/strip_attachments.py plan --help`).
4. **Branch protection / CI** per D2 (add to identity `code_repositories` only if going full model;
   that is a separate terraform PR on the identity stack).
5. **Trim the terraform stack** (separate PR on `terraform`): delete `scripts/` + `.envrc` from
   `client-offboarding/`, rewrite `README.md` to provisioning-only + a pointer to the
   `data-privacy` repo. Keep all `*.tf` / `.lock.hcl` / `stack.tm.hcl`.
6. **Update cross-references:**
   - dot-claude `LGPD-DATA-ERASURE.md` **§8** — the tool now lives in `4shark/data-privacy`
     (`client-offboarding/`); update the "Terraform stack + Python script, terraform repo" line and
     the README pointer (separate dot-claude PR).
   - new repo README ↔ terraform stack README cross-links.
7. **Clean up** — remove the untracked `offboarding-aster/` PII output dir from the terraform working
   tree (move to `/tmp` or delete).

## Cross-references to update (checklist)

- [ ] dot-claude `docs/runbooks/compliance/LGPD-DATA-ERASURE.md` §8 (tool location)
- [ ] terraform `client-offboarding/README.md` → provisioning-only + pointer
- [ ] new repo `README.md` + `client-offboarding/README.md` (run/setup)
- [ ] identity `code_repositories` (only if D2 = full model)

## Risks & rollback

- **No security regression:** the SA key stays in the engineer's own 1P item; the tool's behaviour is
  unchanged. The migration only changes *where the code lives* and *who can read/edit it*.
- **Split-brain references:** until phase 6 is done, the runbook/README point at the old path. Do
  phases 5–6 together (or right after) so docs never point at a moved file.
- **Branch-protection trap (D2):** if `data-privacy` is added to `code_repositories` before the
  age-check workflow exists, PRs on it can't merge. Sequence: workflow first, protection second.
- **Rollback:** the move is additive until phase 5 deletes from terraform. If anything is wrong, the
  terraform copy is still in git history; revert phase 5.

## Done criteria

- `strip_attachments.py` + `.envrc` live only in `4shark/data-privacy` (restricted to the
  `data-privacy` team); terraform `client-offboarding/` holds only the `*.tf` provisioning + a
  pointer README.
- The runbook §8 and both READMEs point at the new location.
- The tool runs from the new repo end-to-end (`plan` → `delete`) for the engineer, with the SA key
  still sourced from their own 1P item.
