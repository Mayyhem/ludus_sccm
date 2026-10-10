# create_demo_users

Every system in this lab logs on as the range-wide domain admin (see `windows_base`'s autologon config), which leaves no low-privileged persona to demo from. This role creates one or more regular domain user accounts, adds them to **Remote Desktop Users** on the host it's assigned to, and optionally to local **Administrators** — useful for demoing things like helpdesk/support account abuse without handing out domain admin.

## What it does

1. Creates each configured domain user account (delegated to the domain controller, so the assigned host doesn't need the ActiveDirectory PowerShell module installed).
2. Enables Remote Desktop on the host this role is assigned to.
3. Adds each account to the local **Remote Desktop Users** group.
4. Adds each account marked `local_admin: true` to the local **Administrators** group.

The role is idempotent — every mutation is guarded, so re-runs are no-ops.

## How to use

Assign the role to a client, depending on `windows_base` for that host and for the DC:

```yaml
- vm_name: "{{ range_id }}-ps1-dev"
  hostname: "ps1-dev"
  ...
  roles:
    - name: mayyhem.ludus_sccm.windows_base
    - name: mayyhem.ludus_sccm.create_demo_users
      depends_on:
        - vm_name: "{{ range_id }}-ps1-dev"
          role: mayyhem.ludus_sccm.windows_base
        - vm_name: "{{ range_id }}-dc"
          role: mayyhem.ludus_sccm.windows_base
```

## Role variables

Overridable in `role_vars`. Default is in `defaults/main.yml`.

| Variable | Default | Purpose |
|---|---|---|
| `ludus_sccm_demo_users` | see below | List of `{ username, password, local_admin }` accounts to create. |

Default:

```yaml
ludus_sccm_demo_users:
  - username: domainuser
    password: 'Password123'
    local_admin: false
  - username: helpdesk
    password: 'Password123'
    local_admin: true
```

`domainuser` is a plain domain account (RDP only). `helpdesk` also gets local admin on the assigned host, to demo a realistic "support account with local admin" misconfiguration.

## Reverting

The role does not ship an "uninstall." To remove an account entirely, delete it from AD (`Remove-ADUser`) on the DC; to just revoke access, remove it from the **Administrators** and/or **Remote Desktop Users** local groups on the host.
