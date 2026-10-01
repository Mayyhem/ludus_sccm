# takeover_9_setup

Deliberate misconfiguration for reproducing [TAKEOVER-9](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/TAKEOVER/TAKEOVER-9/takeover-9_description.md) from the Misconfiguration Manager project.

This role stands up a third-party SQL Server instance on the target host with a linked server pointing at an SCCM site database, storing a fixed SQL credential granted `sysadmin` on the site database. That is exactly the misconfiguration TAKEOVER-9 targets — see the MM description for the abuse scenario. Once applied, an attacker on the third-party host can enumerate linked servers and use `EXECUTE ('...') AT [SCCMSITEDB]` (or `SQLRecon`'s query mode) to run arbitrary T-SQL on the site database as SA.

**Do not run this in an environment where an attacker could reach the third-party host.**

## What it does

1. Installs SQL Server 2022 on the current host (SQL feature only, `NT AUTHORITY\SYSTEM` service account, domain admin as SA). Same install path and PID used by `install_site_database`.
2. Asserts the modern `MSOLEDBSQL` OLE DB provider is registered on this host (SQL 2022 install ships it).
3. Delegates to the target site database VM (default `ps1-db`) to enable **Mixed Mode authentication** — writes `LoginMode = 2` to the SQL 2022 instance registry key, restarts `MSSQLSERVER`, waits for it to come back. Windows-only auth is the SCCM default; stored SQL credentials in a linked server require SQL authentication to be enabled on the target.
4. Creates a SQL login on the target site DB with a fixed password (default `sccm_link` / `Password123`) and grants `sysadmin`.
5. On the third-party host, creates a linked server named `SCCMSITEDB` pointing at the target site DB via `MSOLEDBSQL`, with fixed remote credentials of that SQL login (`uses_self_credential = 0`).
6. Verifies the pivot by running `OPENQUERY([SCCMSITEDB], 'SELECT @@servername, IS_SRVROLEMEMBER(''sysadmin'')')` from the third-party host and printing the result. On success the debug output shows the target hostname and `1`.

The role is idempotent — every mutation is guarded, so re-runs are no-ops.

## How to use

Add a host to the range that represents the third-party product's SQL host. Assign this role to it, and depend on `windows_base` for the host itself and `install_site_database` for the target site DB:

```yaml
- vm_name: "{{ range_id }}-monitor"
  hostname: "monitor"
  template: win2022-server-x64-template
  domain:
    fqdn: mayyhem.com
    role: member
  roles:
    - name: mayyhem.ludus_sccm.windows_base
    - name: mayyhem.ludus_sccm.takeover_9_setup
      depends_on:
        - vm_name: "{{ range_id }}-monitor"
          role: mayyhem.ludus_sccm.windows_base
        - vm_name: "{{ range_id }}-ps1-db"
          role: mayyhem.ludus_sccm.install_site_database
  role_vars:
    ludus_sccm_takeover9_target_vm_name: 'ps1-db'
```

## Role variables

All overridable in `role_vars`. Defaults are in `defaults/main.yml`.

| Variable | Default | Purpose |
|---|---|---|
| `ludus_sccm_takeover9_target_vm_name` | `ps1-db` | Inventory hostname of the SCCM site DB VM. Role delegates to this host for Mixed Mode + SQL login. |
| `ludus_sccm_takeover9_target_fqdn` | `<target_vm_name>.<domain_fqdn>` | Data source in `sp_addlinkedserver`. |
| `ludus_sccm_takeover9_link_name` | `SCCMSITEDB` | Name of the linked server on the third-party host. Matches the name used in the MM description. |
| `ludus_sccm_takeover9_sql_login` | `sccm_link` | SQL login created on the target and stored as the linked-server credential. |
| `ludus_sccm_takeover9_sql_password` | `Password123` | Password for that SQL login. Lab-grade; override for anything non-throwaway. |
| `ludus_sccm_takeover9_sql_regpath` | `HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer` | Registry path of the SQL 2022 default instance on the target. Override if the target uses a non-default instance. |

## Attack demo, once the role has run

From the third-party host:

```powershell
sqlcmd -E -Q "SELECT name, data_source FROM sys.servers WHERE server_id <> 0"
# → SCCMSITEDB   ps1-db.mayyhem.com

sqlcmd -E -Q "EXEC ('SELECT @@servername, IS_SRVROLEMEMBER(''sysadmin'')') AT [SCCMSITEDB]"
# → ps1-db     1

# From there, follow TAKEOVER-1's post-exploitation to insert yourself into
# RBAC_Admins on the site database.
```

Or use [SQLRecon](https://github.com/skahwah/SQLRecon)'s linked-server modes against the third-party SQL directly.

## Reverting

The role does not ship an "uninstall." The manual undo is:

1. On the third-party host: `EXEC sp_dropserver 'SCCMSITEDB', 'droplogins';`
2. On the target site DB: `EXEC sp_dropsrvrolemember @loginame = 'sccm_link', @rolename = 'sysadmin'; DROP LOGIN sccm_link;`. Optionally set `LoginMode` back to `1` under the SQL 2022 instance registry key and restart `MSSQLSERVER` — but this only matters if the deployer wants to remove Mixed Mode; the site DB works fine with it enabled.
3. Delete the third-party host VM from the range.

None of these touch SCCM's own site DB schema or Service Broker replication.

## References

- Misconfiguration Manager, [TAKEOVER-9](https://github.com/subat0mik/Misconfiguration-Manager/blob/main/attack-techniques/TAKEOVER/TAKEOVER-9/takeover-9_description.md).
- Sanjiv Kawa, [SQLRecon](https://github.com/skahwah/SQLRecon).
