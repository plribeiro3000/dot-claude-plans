# SPIKE — Executing the initial integrator SQL script on a remote MSSQL database from Ubuntu Linux

**Conducted by:** Pedro Ribeiro
**Date:** 2026-03-30
**Status:** Closed — see conclusions

---

## Goal

How to execute the integrator's initial SQL script (`Integrador-4Shark-MSSQL-Prefixo-3.0-p1.sql`) on a client's MSSQL database from an Ubuntu Linux machine, without requiring a Windows server or direct SSMS access?

The script is normally executed by the client, but when the client is unresponsive, the 4Shark team needs a way to provision the database infrastructure themselves.

---

## Method

- Analyzed the SQL script structure and requirements
- Reviewed the integrator codebase for existing MSSQL connection mechanisms (TinyTDS, Sequel)
- Evaluated available CLI tools for MSSQL on Linux

---

## Evidence

### Script characteristics

- 1476 lines, 14 tables, 30+ stored procedures, indexes, foreign keys, collation changes
- Uses **88 `GO` batch separators** — `GO` is a client-side command, not SQL
- Uses named transactions (`BEGIN TRANSACTION TABLES ... COMMIT TRANSACTION TABLES`)
- Must be executed in sequence (tables → collation → foreign keys → indexes → procedures → version insert)

### Option 1: `sqlcmd` on Ubuntu (recommended)

Microsoft's official CLI. Handles `GO` natively because it was designed for it.

**Installation:**

```bash
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18 mssql-tools18
```

**Execution:**

```bash
sqlcmd -S <host>,<port> -U <user> -P '<password>' -d <database> -i Integrador-4Shark-MSSQL-Prefixo-3.0-p1.sql
```

**On macOS (for local testing):**

```bash
brew install microsoft/mssql-release/mssql-tools18
```

### Option 2: TinyTDS via Ruby (viable but fragile)

The integrator already uses TinyTDS + Sequel for runtime queries. Could be used to execute the script, but:

- TinyTDS does **not** understand `GO` — would need to split the file manually by `GO` and execute each batch separately
- Error handling and transaction management become the caller's responsibility
- Stored procedure creation requires isolated batches — a single missed split breaks everything

### Option 3: Windows VM (unnecessary)

Spinning up a Windows machine just to run SSMS is overkill. `sqlcmd` does the same thing.

### Network access

The integrator's EC2 instance already has network access to the client's MSSQL server (it runs the integration). Installing `sqlcmd` on that EC2 is the path of least resistance — no firewall or VPN issues.

---

## Conclusions

1. **`sqlcmd` on the integrator's EC2 instance is the best approach** — it handles `GO` natively, requires minimal setup (apt install), and the network path to the client's MSSQL is already open
2. **TinyTDS works but is unnecessarily complex** for DDL scripts with batch separators
3. **No Windows machine is needed** — `sqlcmd` is fully supported on Linux
4. **macOS is also an option** if the operator's machine has direct network access to the client's MSSQL

---

## Next Steps

- No PLAN.md needed — this is an operational procedure, not a feature
- When needed: install `sqlcmd` on the target EC2, copy the SQL file, execute it
- Consider documenting this as a runbook if it becomes a recurring need

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
